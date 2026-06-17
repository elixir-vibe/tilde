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
  def load_session(session_id), do: {:ok, Tilde.session(id: session_id)}

  @impl true
  def save_state(session) do
    notify({:storage_save_state, session.id, session.input.value})
    :ok
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

defmodule TildeTest.LLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def respond(session, _opts), do: {:ok, "echo: #{Tilde.Runtime.LLM.latest_user_text(session)}"}
end

defmodule TildeTest.FailingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def respond(_session, _opts), do: {:error, :boom}
end

defmodule TildeTest.StreamingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def respond(_session, _opts), do: {:ok, "unused"}

  @impl true
  def stream(_session, _opts), do: [{:delta, "hel"}, {:delta, "lo"}, {:done, "hello"}]
end

defmodule TildeTest.ToolStreamingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def respond(_session, _opts), do: {:ok, "unused"}

  @impl true
  def stream(_session, _opts) do
    [
      {:tool_started, "tool_utc", "utc_now", %{}},
      {:tool_done, "tool_utc", :success, %{utc_now: "2026-06-14T00:00:00Z"}},
      {:delta, "done"},
      {:done, "done"}
    ]
  end
end

defmodule TildeTest.CrashingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def respond(_session, _opts), do: {:ok, "unused"}

  @impl true
  def stream(_session, _opts), do: raise("boom")
end

defmodule TildeTest.BlockingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def respond(_session, _opts), do: {:ok, "unused"}

  @impl true
  def stream(session, _opts) do
    test_pid = Application.fetch_env!(:tilde, :blocking_llm_test_pid)
    send(test_pid, {:blocking_llm_started, self(), Tilde.Runtime.LLM.latest_user_text(session)})

    receive do
      :release_blocking_llm -> [{:done, "reply: #{Tilde.Runtime.LLM.latest_user_text(session)}"}]
    after
      1_000 -> [{:error, :timeout}]
    end
  end
end
