defmodule Tilde.Runtime.LLM.Provider.Jido do
  @moduledoc """
  Jido.AI ReAct-backed LLM backend for Tilde.

  This provider returns Jido's canonical `Jido.AI.Runtime.Event` stream directly.
  Tilde owns session/event projection; Jido owns model routing, ReAct iteration,
  tool execution, and runtime event contracts.
  """

  @behaviour Tilde.Runtime.LLM.Provider

  alias Jido.AI.Runtime.Event, as: RuntimeEvent
  alias Tilde.Core.{Block, Session}
  alias Tilde.Runtime.LLM
  alias Tilde.Session.AgentLoop.ResumeCandidate
  alias Tilde.Session.Compaction

  @system_prompt """
  You are Tilde, a concise coding assistant running inside a shared semantic console.
  Respond briefly. Use the available tools when you need to inspect files, edit files, write files, or run shell commands.
  Use list to inspect directories and read to examine regular files instead of cat or sed. Use bash for shell-only operations such as rg, find, git, and mix. Use edit for precise exact-text replacements.
  After tool use, always finish with a concise answer that summarizes what you found or changed.
  """

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
        session
        |> query(opts)
        |> Jido.AI.Reasoning.ReAct.stream(react_config(opts), react_opts(session))
        |> adapt_react_events()

      {:error, reason} ->
        [failed_event(reason)]
    end
  rescue
    exception in @runtime_errors -> [failed_event(exception)]
  end

  @impl true
  def resume_checkpoint(%Session{} = session, %ResumeCandidate{} = candidate, opts \\ []) do
    case ensure_openrouter_key() do
      :ok ->
        candidate.checkpoint_token
        |> Jido.AI.Reasoning.ReAct.continue(react_config(opts), react_opts(session))
        |> case do
          {:ok, %{events: events}} -> events |> adapt_react_events() |> Enum.to_list()
          {:error, reason} -> [failed_event(reason)]
        end

      {:error, reason} ->
        [failed_event(reason)]
    end
  rescue
    exception in @runtime_errors -> [failed_event(exception)]
  end

  @impl true
  def cancel_checkpoint(token, opts \\ []) when is_binary(token) do
    Jido.AI.Reasoning.ReAct.cancel(token, react_config(opts), :user_aborted)
  rescue
    exception in @runtime_errors -> {:error, exception}
  end

  defp react_config(opts) do
    [
      model: Keyword.get(opts, :model, LLM.model()),
      system_prompt: Keyword.get(opts, :system_prompt, @system_prompt),
      tools: Keyword.get(opts, :tools, Tilde.Tools.coding_tools()),
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      max_tokens: Keyword.get(opts, :max_tokens, 800),
      streaming: true,
      timeout_ms: Keyword.get(opts, :timeout, 30_000),
      llm_opts: llm_opts(opts)
    ]
  end

  defp react_opts(%Session{} = session) do
    [
      context: %{session_id: session.id, messages: history_messages(session)}
    ]
  end

  defp llm_opts(opts) do
    [
      provider_options: [
        app_referer: Keyword.get(opts, :app_referer, "https://tilde.elixir.toys"),
        app_title: Keyword.get(opts, :app_title, "Tilde")
      ]
    ]
  end

  # Temporary private bridge for released jido_ai versions where ReAct streams
  # `Jido.AI.Reasoning.ReAct.Event` instead of canonical runtime events.
  # Remove after agentjido/jido_ai#314 lands and Tilde bumps to that release.
  defp adapt_react_events(events) do
    Stream.flat_map(events, &adapt_react_event/1)
  end

  defp adapt_react_event(%Jido.AI.Reasoning.ReAct.Event{kind: :input_injected}), do: []

  defp adapt_react_event(%Jido.AI.Reasoning.ReAct.Event{} = event) do
    [event |> Map.from_struct() |> RuntimeEvent.new()]
  end

  defp adapt_react_event(%RuntimeEvent{} = event), do: [event]

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
