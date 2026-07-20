defmodule TildeTest.MarkdownBackend do
  @behaviour Tilde.Runtime.Markdown.Provider

  @impl true
  def to_html(markdown, _opts), do: {:ok, "<p>fake #{markdown}</p>"}
end

defmodule TildeTest.KeyProvider do
  @behaviour Tilde.Transport.SSH.KeyProvider

  @impl true
  def ensure_system_dir(path, _opts), do: {:ok, path}
end

defmodule TildeTest.StorageAdapter do
  @behaviour Tilde.Storage

  @impl true
  def ensure_session(session) do
    notify({:storage_ensure_session, session.id})
    :ok
  end

  @impl true
  def append_event(session, event) do
    notify({:storage_append_event, session.id, event.type, event.text})
    :ok
  end

  @impl true
  def load_events(_session_id), do: {:ok, []}

  @impl true
  def load_session(session_id) do
    session =
      case Application.get_env(:tilde, :storage_load_session) do
        fun when is_function(fun, 1) -> fun.(session_id)
        _other -> Tilde.session(id: session_id)
      end

    {:ok, session}
  end

  @impl true
  def save_state(session) do
    notify({:storage_save_state, session.id, session.input.value})
    notify({:storage_save_state_metadata, session.id, session.metadata})
    :ok
  end

  @impl true
  def session_summaries(_opts) do
    {:ok, Application.get_env(:tilde, :storage_session_summaries, [])}
  end

  @impl true
  def search(_query, _opts), do: {:ok, []}

  defp notify(message) do
    if pid = Application.get_env(:tilde, :storage_test_pid) do
      send(pid, message)
    end
  end
end

defmodule TildeTest.ToolRenderer do
  @behaviour Tilde.Tool.Viewer

  @impl true
  def call(block) do
    Tilde.Tool.View.call("custom",
      segments: [%{text: block.args.value, color: :success}],
      tags: ["demo"]
    )
  end

  @impl true
  def result(_block, _opts), do: Tilde.Tool.View.result(lines: ["custom result"])
end

defmodule TildeTest.RuntimeEvents do
  def started do
    event(:turn_started, %{})
  end

  def checkpoint(token) do
    event(:turn_hibernated, %{token: token})
  end

  def cancelled do
    event(:turn_failed, %{reason: :cancelled})
  end

  def llm_started(model \\ "openrouter/test-model") do
    event(:effect_started, %{call_id: "llm-call", model: model, message_count: 2},
      effect_id: "llm-call",
      effect_kind: :llm
    )
  end

  def llm_completed(usage \\ %{input_tokens: 12, output_tokens: 5}) do
    event(
      :effect_completed,
      %{call_id: "llm-call", model: "openrouter/test-model", usage: usage, finish_reason: :stop},
      effect_id: "llm-call",
      effect_kind: :llm
    )
  end

  def delta(text) do
    event(:llm_delta, %{delta: text, chunk_type: :content})
  end

  def thinking_delta(text) do
    event(:llm_delta, %{delta: text, chunk_type: :thinking})
  end

  def tool_started(id, name, args) do
    event(:effect_started, %{arguments: args},
      effect_id: id,
      effect_kind: :operation,
      operation: name
    )
  end

  def tool_completed(id, name, result) do
    event(:effect_completed, %{result: {:ok, result}},
      effect_id: id,
      effect_kind: :operation,
      operation: name
    )
  end

  def completed(result, data \\ %{}) when is_map(data) do
    event(:turn_finished, Map.put(data, :result, result))
  end

  def failed(reason) do
    event(:turn_failed, %{reason: reason})
  end

  defp event(kind, data, opts \\ []) do
    Jidoka.Event.build(kind, [],
      seq: System.unique_integer([:positive]),
      agent_id: "test-run",
      request_id: "test-request",
      loop_index: 0,
      effect_id: Keyword.get(opts, :effect_id),
      effect_kind: Keyword.get(opts, :effect_kind),
      operation: Keyword.get(opts, :operation),
      data: data
    )
  end
end
