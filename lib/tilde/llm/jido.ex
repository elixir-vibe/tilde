defmodule Tilde.LLM.Jido do
  @moduledoc """
  Jido.AI-backed LLM backend for Tilde.

  This starts a short-lived `Tilde.Agent` instance for each response. The public
  Tilde event log remains the source of truth; Jido owns model routing, ReAct
  runtime, and future tool orchestration.
  """

  @behaviour Tilde.LLM.Backend

  alias Tilde.{LLM, Session}

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
           Tilde.Agent.ask_stream(pid, LLM.prompt(session), ask_opts(opts)) do
      stream_agent_events(pid, events)
    else
      {:error, reason} -> [{:error, reason}]
      other -> [{:error, other}]
    end
  end

  defp ask_agent(pid, %Session{} = session, opts) do
    with {:ok, answer} <- Tilde.Agent.ask_sync(pid, LLM.prompt(session), ask_opts(opts)) do
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
    case Map.get(data, :delta, Map.get(data, "delta", "")) do
      text when is_binary(text) and text != "" -> [{:delta, text}]
      _other -> []
    end
  end

  defp jido_event_to_stream_events(%{kind: :request_completed, data: data}) do
    [{:done, data |> Map.get(:result, Map.get(data, "result", "")) |> to_string()}]
  end

  defp jido_event_to_stream_events(%{kind: :request_failed, data: data}) do
    reason = Map.get(data, :error, Map.get(data, "error", data))
    [{:error, reason}]
  end

  defp jido_event_to_stream_events(_event), do: []

  defp ensure_openrouter_key do
    case System.get_env("OPENROUTER_API_KEY") do
      key when is_binary(key) ->
        if String.trim(key) == "", do: {:error, :missing_openrouter_api_key}, else: :ok

      _other ->
        {:error, :missing_openrouter_api_key}
    end
  end

  defp ensure_jido_available do
    if Code.ensure_loaded?(Jido.AgentServer) and Code.ensure_loaded?(Tilde.Agent) and
         function_exported?(Tilde.Agent, :ask_sync, 3) do
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
      id: "tilde-#{session.id}-#{System.unique_integer([:positive])}"
    )
  end

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
