defmodule Tilde.Runtime.LLM.Provider.Jido do
  @moduledoc """
  Jido.AI-backed LLM backend for Tilde.

  This starts a short-lived `Tilde.Agent` instance for each response. The public
  Tilde event log remains the source of truth; Jido owns model routing, ReAct
  runtime, and future tool orchestration.
  """

  @behaviour Tilde.Runtime.LLM.Provider

  alias Tilde.Core.{Block, Session}
  alias Tilde.Runtime.LLM

  @impl true
  def respond(%Session{} = session, opts \\ []) do
    with :ok <- ensure_openrouter_key(),
         :ok <- ensure_jido_available(),
         {:ok, _pid} <- ensure_jido_runtime(),
         :ok <- configure_model_alias(opts),
         {:ok, pid} <- start_agent(session) do
      ask_agent(pid, session, opts)
    end
  end

  @impl true
  def stream(%Session{} = session, opts \\ []) do
    with :ok <- ensure_openrouter_key(),
         :ok <- ensure_jido_available(),
         {:ok, _pid} <- ensure_jido_runtime(),
         :ok <- configure_model_alias(opts),
         {:ok, pid} <- start_agent(session),
         {:ok, %{events: events}} <-
           Tilde.Agent.ask_stream(pid, query(session), ask_opts(opts)) do
      stream_agent_events(pid, events)
    else
      {:error, reason} -> [{:error, reason}]
      other -> [{:error, other}]
    end
  end

  defp ask_agent(pid, %Session{} = session, opts) do
    with {:ok, answer} <- Tilde.Agent.ask_sync(pid, query(session), ask_opts(opts)) do
      {:ok, to_string(answer)}
    end
  after
    if Process.alive?(pid), do: GenServer.stop(pid)
  end

  defp stream_agent_events(pid, events) do
    Stream.transform(
      events,
      fn -> nil end,
      fn event, acc -> {jido_event_to_stream_events(event), acc} end,
      fn _acc -> if Process.alive?(pid), do: GenServer.stop(pid) end
    )
  end

  defp jido_event_to_stream_events(%{kind: :llm_delta, data: data}) do
    chunk_type = event_field(data, :chunk_type)

    case {chunk_type, event_field(data, :delta, "")} do
      {type, text} when type in [:content, "content"] and is_binary(text) and text != "" ->
        [{:delta, text}]

      _other ->
        []
    end
  end

  defp jido_event_to_stream_events(%{kind: :tool_started, data: data} = event) do
    id = event.tool_call_id || event_field(data, :tool_call_id)
    name = event.tool_name || event_field(data, :tool_name, "tool")
    args = event_field(data, :arguments, %{})
    [{:tool_started, id, name, args}]
  end

  defp jido_event_to_stream_events(%{kind: :tool_completed, data: data} = event) do
    id = event.tool_call_id || event_field(data, :tool_call_id)
    raw_result = event_field(data, :result)
    status = tool_status(raw_result)
    result = tool_result(raw_result)
    [{:tool_done, id, status, result}]
  end

  defp jido_event_to_stream_events(%{kind: :request_completed, data: data}) do
    [{:done, data |> event_field(:result, "") |> to_string()}]
  end

  defp jido_event_to_stream_events(%{kind: :request_failed, data: data}) do
    reason = event_field(data, :error, data)
    [{:error, reason}]
  end

  defp jido_event_to_stream_events(_event), do: []

  defp event_field(data, key, default \\ nil) when is_atom(key) do
    Map.get(data, key, Map.get(data, Atom.to_string(key), default))
  end

  defp tool_status({:ok, _result, _meta}), do: :success
  defp tool_status({:ok, _result}), do: :success
  defp tool_status(_other), do: :error

  defp tool_result({:ok, result, _meta}), do: result
  defp tool_result({:ok, result}), do: result
  defp tool_result(result), do: result

  defp ensure_openrouter_key do
    case System.get_env("OPENROUTER_API_KEY") do
      key when is_binary(key) ->
        if String.trim(key) == "", do: {:error, :missing_openrouter_api_key}, else: :ok

      _other ->
        {:error, :missing_openrouter_api_key}
    end
  end

  defp ensure_jido_available do
    if Code.ensure_loaded?(Jido.AgentServer) and Code.ensure_loaded?(Jido.AI.Context) and
         Code.ensure_loaded?(Tilde.Agent) and function_exported?(Tilde.Agent, :ask_sync, 3) do
      :ok
    else
      {:error, :jido_ai_not_available}
    end
  end

  defp ensure_jido_runtime, do: Jido.start(name: Jido)

  defp configure_model_alias(opts) do
    model = Keyword.get(opts, :model, LLM.model())
    aliases = Application.get_env(:jido_ai, :model_aliases, %{})
    Application.put_env(:jido_ai, :model_aliases, Map.put(aliases, :tilde_haiku, model))
    :ok
  end

  defp start_agent(%Session{} = session) do
    Jido.start_agent(
      Jido,
      Tilde.Agent,
      id: "tilde-#{session.id}-#{System.unique_integer([:positive])}",
      initial_state: %{context: jido_context(session)}
    )
  end

  defp jido_context(%Session{} = session) do
    Jido.AI.Context.new()
    |> Jido.AI.Context.append_messages(history_messages(session))
  end

  defp history_messages(%Session{} = session) do
    session.transcript.blocks
    |> drop_latest_user_message()
    |> Enum.flat_map(&message_block/1)
  end

  defp message_block(%Block{kind: :message, role: :user, source: source}) when is_binary(source),
    do: [%{role: :user, content: source}]

  defp message_block(%Block{kind: :message, role: :assistant, source: source})
       when is_binary(source),
       do: [%{role: :assistant, content: source}]

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

  defp query(%Session{} = session), do: LLM.latest_user_text(session) || LLM.prompt(session)

  defp ask_opts(opts) do
    [
      timeout: Keyword.get(opts, :timeout, 30_000),
      llm_opts: [
        provider_options: [
          app_referer: Keyword.get(opts, :app_referer, "https://tilde.elixir.toys"),
          app_title: Keyword.get(opts, :app_title, "Tilde")
        ]
      ]
    ]
  end
end
