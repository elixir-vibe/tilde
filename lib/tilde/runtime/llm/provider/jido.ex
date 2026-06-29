defmodule Tilde.Runtime.LLM.Provider.Jido do
  @moduledoc """
  Jidoka-backed LLM backend for Tilde.

  Tilde owns session/event projection; Jidoka owns model routing, turn execution,
  effect interpretation, and operation journaling.
  """

  @behaviour Tilde.Runtime.LLM.Provider

  alias Jidoka.Agent
  alias Jidoka.Runtime.JidoActions
  alias Jidoka.Runtime.ReqLLM, as: JidokaReqLLM
  alias Tilde.Core.{Block, Session}
  alias Tilde.Runtime.LLM
  alias Tilde.Session.AgentLoop.ResumeCandidate
  alias Tilde.Session.Compaction

  @system_prompt """
  You are Tilde, a concise coding assistant running inside a shared semantic console.
  Respond briefly. Use the available tools when you need to inspect files, edit files, write files, or run shell commands.
  Use read to examine regular files instead of cat or sed. Use bash for shell-only operations such as ls, rg, find, git, and mix. Use edit for precise exact-text replacements.
  After tool use, always finish with a concise answer that summarizes what you found or changed.
  """

  @compaction_system_prompt """
  You write handoff summaries for a coding-agent conversation.

  Critical rules:
  - Summarize only facts explicitly present in the transcript.
  - Do not answer the user's request, continue the task, or invent actions taken.
  - If the transcript contains `/showcase`, treat the following showcase content as demo/sample fixture content, not as the user's actual task.
  - If the transcript is demo/sample content, say that it is demo/sample content.
  - Preserve decisions, preferences, constraints, completed work, current state, files, commands, validation status, blockers, and next steps when present.
  - Return only markdown.
  - Start with exactly: ## Context Compaction
  - Prefer these sections when relevant: Goal, Constraints and preferences, Completed work, Current state, Important files or commands, Next steps.
  - If no real next step is explicit in the transcript, write "Not specified" rather than inventing one.
  """

  @default_max_model_turns 1_000_000

  @runtime_errors [
    RuntimeError,
    ArgumentError,
    ArithmeticError,
    MatchError,
    FunctionClauseError,
    CaseClauseError,
    CondClauseError,
    WithClauseError,
    KeyError,
    BadMapError,
    Protocol.UndefinedError,
    UndefinedFunctionError
  ]

  @impl true
  def stream(%Session{} = session, opts \\ []) do
    case ensure_openrouter_key() do
      :ok ->
        run_turn_stream(session, query(session, opts), opts)

      {:error, reason} ->
        [failed_event(reason)]
    end
  rescue
    exception in @runtime_errors -> [failed_event(exception)]
  end

  @impl true
  def resume_checkpoint(%Session{} = _session, %ResumeCandidate{} = candidate, opts \\ []) do
    case ensure_openrouter_key() do
      :ok ->
        resume_turn_stream(candidate.checkpoint_token, opts)

      {:error, reason} ->
        [failed_event(reason)]
    end
  rescue
    exception in @runtime_errors -> [failed_event(exception)]
  end

  def summarize_compaction(blocks, opts \\ []) when is_list(blocks) do
    case ensure_openrouter_key() do
      :ok ->
        blocks
        |> compaction_messages(opts)
        |> generate_compaction_summary(opts)

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception in @runtime_errors -> {:error, exception}
  end

  @impl true
  def cancel_checkpoint(token, _opts \\ []) when is_binary(token) do
    {:ok, token}
  end

  defp generate_compaction_summary(messages, opts) do
    with {:ok, response} <-
           ReqLLM.generate_text(
             Keyword.get(opts, :model, LLM.model()),
             messages,
             compaction_llm_opts(opts)
           ),
         text when is_binary(text) <- ReqLLM.Response.text(response),
         summary when summary != "" <- normalize_compaction_summary(text) do
      {:ok, summary}
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :empty_compaction_summary}
    end
  end

  defp compaction_llm_opts(opts) do
    [
      max_tokens: Keyword.get(opts, :max_tokens, 1_200),
      temperature: Keyword.get(opts, :temperature, 0.1),
      provider_options: provider_options(opts)
    ]
  end

  defp compaction_messages(blocks, opts) do
    instructions = Keyword.get(opts, :instructions)

    [
      %{role: "system", content: @compaction_system_prompt},
      %{role: "user", content: compaction_user_prompt(blocks, instructions)}
    ]
  end

  defp compaction_user_prompt(blocks, instructions) do
    [
      custom_instructions_text(instructions),
      "Summarize the transcript between <conversation> tags. Do not continue it.",
      "",
      "<conversation>",
      Enum.map_join(blocks, "\n\n", &compaction_block_text/1),
      "</conversation>"
    ]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp custom_instructions_text(nil), do: ""

  defp custom_instructions_text(instructions) when is_binary(instructions) do
    instructions = String.trim(instructions)
    if instructions == "", do: "", else: "User compaction instructions: #{instructions}\n"
  end

  defp compaction_block_text(%Block{role: role, source: source}) do
    "<message role=#{inspect(to_string(role))}>\n#{String.trim(source || "")}\n</message>"
  end

  defp normalize_compaction_summary(text) do
    summary = String.trim(text)

    cond do
      summary == "" ->
        ""

      String.starts_with?(summary, "## Context Compaction") ->
        summary

      true ->
        "## Context Compaction\n\n#{summary}"
    end
  end

  defp run_turn_stream(%Session{} = session, query, opts) do
    with {:ok, agent} <- jidoka_agent(opts),
         {:ok, request} <- turn_request(session, query, opts),
         {:ok, async} <- start_async_turn(agent, request, opts) do
      async
      |> Jidoka.stream(stream_opts(opts))
      |> Stream.map(&enrich_terminal_event(&1, async, opts))
    else
      {:error, reason} -> [failed_event(reason)]
    end
  end

  defp resume_turn_stream(snapshot_token, opts) do
    case start_async_resume(snapshot_token, opts) do
      {:ok, async} ->
        async
        |> Jidoka.stream(stream_opts(opts))
        |> Stream.map(&enrich_terminal_event(&1, async, opts))

      {:error, reason} ->
        [failed_event(reason)]
    end
  end

  defp start_async_turn(agent, request, opts) do
    runtime_opts = Keyword.put(runtime_opts(opts), :request_id, request.request_id)

    Jidoka.Chat.Request.start_fun(agent, request.input, runtime_opts, fn prepared_opts ->
      Jidoka.turn(agent, request, prepared_opts)
    end)
  end

  defp start_async_resume(snapshot_token, opts) do
    Jidoka.Chat.Request.start_fun(
      snapshot_token,
      "resume",
      runtime_opts(opts),
      fn prepared_opts ->
        Jidoka.resume(snapshot_token, prepared_opts)
      end
    )
  end

  defp jidoka_agent(opts) do
    Jidoka.agent(
      id: Keyword.get(opts, :agent_id, "tilde"),
      instructions: Keyword.get(opts, :system_prompt, @system_prompt),
      model: Keyword.get(opts, :model, LLM.model()),
      generation: generation(opts),
      operations: JidoActions.operations_from_actions(jido_actions(opts)),
      runtime_defaults: %{
        provider: :tilde,
        max_model_turns: max_model_turns(opts),
        timeout_ms: Keyword.get(opts, :timeout, 30_000)
      }
    )
  end

  defp turn_request(%Session{} = session, query, opts) do
    attrs = [
      input: query,
      context: %{session_id: session.id},
      agent_state: Agent.State.new!(messages: history_messages(session))
    ]

    attrs =
      case Keyword.get(opts, :request_id) do
        request_id when is_binary(request_id) and request_id != "" ->
          Keyword.put(attrs, :request_id, request_id)

        _request_id ->
          attrs
      end

    Jidoka.Turn.Request.from_input(attrs)
  end

  defp generation(opts) do
    %{
      params: %{
        max_tokens: Keyword.get(opts, :max_tokens, 800),
        temperature: Keyword.get(opts, :temperature, 0.0),
        timeout: Keyword.get(opts, :timeout, 30_000)
      },
      provider_options: provider_options(opts) |> Map.new()
    }
  end

  defp runtime_opts(opts) do
    [
      llm: Keyword.get_lazy(opts, :llm, fn -> jidoka_llm(opts) end),
      operations:
        JidoActions.operations(jido_actions(opts), context: Keyword.get(opts, :context, %{})),
      checkpoint: Keyword.get(opts, :checkpoint, :none),
      timeout: Keyword.get(opts, :timeout, 30_000),
      max_model_turns: max_model_turns(opts),
      stream: true
    ]
  end

  defp jidoka_llm(opts) do
    JidokaReqLLM.llm(
      model: Keyword.get(opts, :model, LLM.model()),
      max_tokens: Keyword.get(opts, :max_tokens, 800),
      temperature: Keyword.get(opts, :temperature, 0.0),
      timeout: Keyword.get(opts, :timeout, 30_000),
      provider_options: provider_options(opts),
      stream: true
    )
  end

  defp stream_opts(opts), do: [stream_event_timeout_ms: Keyword.get(opts, :timeout, 30_000)]

  defp max_model_turns(opts) do
    Keyword.get_lazy(opts, :max_model_turns, fn ->
      Keyword.get_lazy(opts, :max_iterations, fn ->
        Application.get_env(:tilde, :llm_max_iterations, @default_max_model_turns)
      end)
    end)
  end

  defp jido_actions(opts), do: Keyword.get(opts, :tools, Tilde.Tools.coding_tools())

  defp provider_options(opts) do
    [app_title: Keyword.get(opts, :app_title, "Tilde")]
    |> maybe_put_app_referer(app_referer(opts))
  end

  defp app_referer(opts) do
    Keyword.get(opts, :app_referer) || Application.get_env(:tilde, :llm_app_referer)
  end

  defp maybe_put_app_referer(options, nil), do: options
  defp maybe_put_app_referer(options, ""), do: options

  defp maybe_put_app_referer(options, app_referer),
    do: Keyword.put(options, :app_referer, app_referer)

  defp enrich_terminal_event(%Jidoka.Event{event: :turn_finished} = event, async, opts) do
    case Jidoka.await(async, timeout: Keyword.get(opts, :timeout, 30_000)) do
      {:ok, %Jidoka.Turn.Result{} = result} ->
        put_event_data(event, %{result: result.content})

      {:ok, _session, content} when is_binary(content) ->
        put_event_data(event, %{result: content})

      {:ok, content} when is_binary(content) ->
        put_event_data(event, %{result: content})

      {:error, reason} ->
        failed_event(reason)

      _other ->
        event
    end
  end

  defp enrich_terminal_event(%Jidoka.Event{event: :turn_hibernated} = event, async, opts) do
    case Jidoka.await(async, timeout: Keyword.get(opts, :timeout, 30_000)) do
      {:hibernate, snapshot} ->
        put_event_data(event, %{snapshot: serialize_snapshot(snapshot)})

      {:hibernate, _session, snapshot} ->
        put_event_data(event, %{snapshot: serialize_snapshot(snapshot)})

      _other ->
        event
    end
  end

  defp enrich_terminal_event(%Jidoka.Event{} = event, _async, _opts), do: event

  defp put_event_data(%Jidoka.Event{data: data} = event, extra) when is_map(data) do
    %Jidoka.Event{event | data: Map.merge(data, extra)}
  end

  defp serialize_snapshot(snapshot) do
    case Jidoka.Runtime.AgentSnapshot.serialize(snapshot) do
      {:ok, token} -> token
      _other -> snapshot
    end
  end

  defp history_messages(%Session{} = session) do
    session
    |> Compaction.model_context_blocks()
    |> drop_latest_user_message()
    |> Enum.flat_map(&message_block/1)
  end

  defp message_block(%Block{kind: :message, role: :user, source: source}) when is_binary(source),
    do: [%{role: :user, content: source}]

  defp message_block(%Block{kind: :message, role: :assistant, source: source})
       when is_binary(source),
       do: [%{role: :assistant, content: source}]

  defp message_block(%Block{kind: :message, role: :system, source: source})
       when is_binary(source),
       do: [%{role: :user, content: "Compacted prior context:\n\n#{source}"}]

  defp message_block(_block), do: []

  defp drop_latest_user_message(blocks) do
    {blocks, _dropped?} =
      blocks
      |> Enum.reverse()
      |> Enum.reduce({[], false}, fn
        %Block{kind: :message, role: :user}, {acc, false} -> {acc, true}
        block, {acc, dropped?} -> {[block | acc], dropped?}
      end)

    blocks
  end

  defp query(%Session{} = session, opts) do
    Keyword.get(opts, :prompt) || LLM.latest_user_text(session) || LLM.prompt(session)
  end

  defp ensure_openrouter_key do
    case System.get_env("OPENROUTER_API_KEY") do
      key when is_binary(key) ->
        if String.trim(key) == "", do: {:error, :missing_openrouter_api_key}, else: :ok

      _other ->
        {:error, :missing_openrouter_api_key}
    end
  end

  defp failed_event(reason) do
    Tilde.Runtime.LLM.Event.failed(reason, source: "tilde-jido-provider")
  end
end
