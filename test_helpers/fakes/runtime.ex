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
    event(:turn_failed, %{error: reason})
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

defmodule TildeTest.LLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, candidate, _opts) do
    [TildeTest.RuntimeEvents.completed("resumed: #{candidate.checkpoint_token}")]
  end

  @impl true
  def stream(session, opts) do
    prompt = Keyword.get(opts, :prompt) || Tilde.Runtime.LLM.latest_user_text(session)
    [TildeTest.RuntimeEvents.completed("echo: #{prompt}")]
  end
end

defmodule TildeTest.CompactionSummaryLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: []

  @impl true
  def stream(_session, _opts), do: []

  def summarize_compaction(blocks, opts) do
    test_pid = Application.get_env(:tilde, :compaction_summary_test_pid)
    if test_pid, do: send(test_pid, {:summarize_compaction, Enum.map(blocks, & &1.source), opts})
    {:ok, "## Context Compaction\n\nLLM summary"}
  end
end

defmodule TildeTest.EmptyCompactionSummaryLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: []

  @impl true
  def stream(_session, _opts), do: []

  def summarize_compaction(_blocks, _opts), do: {:ok, ""}
end

defmodule TildeTest.FailingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: [TildeTest.RuntimeEvents.failed(:boom)]

  @impl true
  def stream(_session, _opts), do: [TildeTest.RuntimeEvents.failed(:boom)]
end

defmodule TildeTest.BufferedDeltaLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: stream(nil, [])

  @impl true
  def stream(_session, _opts) do
    test_pid = Application.fetch_env!(:tilde, :buffered_delta_llm_test_pid)
    send(test_pid, {:buffered_delta_llm_started, self()})

    Stream.concat(
      [
        TildeTest.RuntimeEvents.delta("he"),
        TildeTest.RuntimeEvents.delta("llo")
      ],
      Stream.resource(
        fn -> :ok end,
        fn
          :ok ->
            receive do
              :finish_buffered_delta_llm -> {[TildeTest.RuntimeEvents.completed("hello")], :done}
            after
              1_000 -> {[TildeTest.RuntimeEvents.failed(:timeout)], :done}
            end

          :done ->
            {:halt, :done}
        end,
        fn _state -> :ok end
      )
    )
  end
end

defmodule TildeTest.StreamingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts) do
    [TildeTest.RuntimeEvents.delta("resumed"), TildeTest.RuntimeEvents.completed("resumed")]
  end

  @impl true
  def stream(_session, _opts) do
    [
      TildeTest.RuntimeEvents.delta("hel"),
      TildeTest.RuntimeEvents.delta("lo"),
      TildeTest.RuntimeEvents.completed("hello")
    ]
  end
end

defmodule TildeTest.BlockingMetadataLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: stream(nil, [])

  @impl true
  def stream(_session, _opts) do
    test_pid = Application.fetch_env!(:tilde, :metadata_llm_test_pid)
    send(test_pid, {:metadata_llm_started, self()})

    Stream.concat(
      [
        TildeTest.RuntimeEvents.started(),
        TildeTest.RuntimeEvents.llm_started("openrouter/semantic-model")
      ],
      Stream.resource(
        fn -> :ok end,
        fn
          :ok ->
            receive do
              :release_metadata_llm ->
                {
                  [
                    TildeTest.RuntimeEvents.llm_completed(%{input_tokens: 21, output_tokens: 8}),
                    TildeTest.RuntimeEvents.checkpoint("checkpoint-semantic"),
                    TildeTest.RuntimeEvents.completed("semantic reply", %{
                      usage: %{input_tokens: 21, output_tokens: 8},
                      termination_reason: :final_answer,
                      thinking_content: "I should answer tersely.",
                      reasoning_details: [%{summary: "reasoned", dropped: self()}]
                    })
                  ],
                  :done
                }
            after
              1_000 -> {[TildeTest.RuntimeEvents.failed(:timeout)], :done}
            end

          :done ->
            {:halt, :done}
        end,
        fn _state -> :ok end
      )
    )
  end
end

defmodule TildeTest.MetadataLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: stream(nil, [])

  @impl true
  def stream(_session, _opts) do
    [
      TildeTest.RuntimeEvents.started(),
      TildeTest.RuntimeEvents.llm_started("openrouter/semantic-model"),
      TildeTest.RuntimeEvents.llm_completed(%{input_tokens: 21, output_tokens: 8}),
      TildeTest.RuntimeEvents.checkpoint("checkpoint-semantic"),
      TildeTest.RuntimeEvents.completed("semantic reply", %{
        usage: %{input_tokens: 21, output_tokens: 8},
        termination_reason: :final_answer,
        thinking_content: "I should answer tersely.",
        reasoning_details: [%{summary: "reasoned"}]
      })
    ]
  end
end

defmodule TildeTest.ThinkingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: stream(nil, [])

  @impl true
  def stream(_session, _opts) do
    test_pid = Application.fetch_env!(:tilde, :thinking_llm_test_pid)
    send(test_pid, {:thinking_llm_started, self()})

    Stream.concat(
      [TildeTest.RuntimeEvents.thinking_delta("thinking")],
      Stream.resource(
        fn -> :ok end,
        fn
          :ok ->
            receive do
              :release_thinking_llm ->
                {[TildeTest.RuntimeEvents.delta("answer")], :content}
            after
              1_000 -> {[TildeTest.RuntimeEvents.failed(:timeout)], :done}
            end

          :content ->
            receive do
              :finish_thinking_llm -> {[TildeTest.RuntimeEvents.completed("answer")], :done}
            after
              1_000 -> {[TildeTest.RuntimeEvents.failed(:timeout)], :done}
            end

          :done ->
            {:halt, :done}
        end,
        fn _state -> :ok end
      )
    )
  end
end

defmodule TildeTest.JidokaToolLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: []

  @impl true
  def stream(session, opts) do
    Tilde.Runtime.LLM.Provider.Jido.stream(
      session,
      Keyword.merge(opts,
        llm: llm(),
        tools: [Tilde.Tools.UtcNow],
        max_model_turns: 3
      )
    )
  end

  defp llm do
    test_pid = Application.fetch_env!(:tilde, :jidoka_tool_llm_test_pid)

    fn _intent, _journal ->
      case Process.get({__MODULE__, :turn}, :operation) do
        :operation ->
          Process.put({__MODULE__, :turn}, :final)
          send(test_pid, :jidoka_tool_llm_operation_requested)
          {:ok, Jidoka.Effect.LLMDecision.operation("utc_now", %{})}

        :final ->
          send(test_pid, :jidoka_tool_llm_final_requested)
          {:ok, Jidoka.Effect.LLMDecision.final("Tool finished.")}
      end
    end
  end
end

defmodule TildeTest.PostToolTerminalLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: stream(nil, [])

  @impl true
  def stream(_session, _opts) do
    [
      TildeTest.RuntimeEvents.delta("Before."),
      TildeTest.RuntimeEvents.tool_started("tool_bash", "bash", %{command: "ls"}),
      TildeTest.RuntimeEvents.tool_completed("tool_bash", "bash", %{
        content: [%{type: "text", text: "README.md"}]
      }),
      TildeTest.RuntimeEvents.delta("After."),
      TildeTest.RuntimeEvents.completed("After.")
    ]
  end
end

defmodule TildeTest.MaxIterationsLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: stream(nil, [])

  @impl true
  def stream(_session, _opts) do
    [
      TildeTest.RuntimeEvents.delta("Let me inspect that:"),
      TildeTest.RuntimeEvents.completed("Maximum iterations reached without a final answer.", %{
        termination_reason: :max_iterations
      })
    ]
  end
end

defmodule TildeTest.ToolStreamingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts) do
    [TildeTest.RuntimeEvents.completed("resumed with tools")]
  end

  @impl true
  def stream(_session, _opts) do
    [
      TildeTest.RuntimeEvents.tool_started("tool_utc", "utc_now", %{}),
      TildeTest.RuntimeEvents.tool_completed("tool_utc", "utc_now", %{
        utc_now: "2026-06-14T00:00:00Z"
      }),
      TildeTest.RuntimeEvents.delta("done"),
      TildeTest.RuntimeEvents.completed("done")
    ]
  end
end

defmodule TildeTest.CancelledLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: [TildeTest.RuntimeEvents.cancelled()]

  @impl true
  def stream(_session, _opts), do: [TildeTest.RuntimeEvents.cancelled()]
end

defmodule TildeTest.CrashingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, _candidate, _opts), do: raise("boom")

  @impl true
  def stream(_session, _opts), do: raise("boom")
end

defmodule TildeTest.BlockingLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts), do: {:ok, token}

  @impl true
  def resume_checkpoint(_session, candidate, _opts) do
    [TildeTest.RuntimeEvents.completed("resumed: #{candidate.checkpoint_token}")]
  end

  @impl true
  def stream(session, opts) do
    prompt = Keyword.get(opts, :prompt) || Tilde.Runtime.LLM.latest_user_text(session)
    test_pid = Application.fetch_env!(:tilde, :blocking_llm_test_pid)
    send(test_pid, {:blocking_llm_started, self(), prompt})

    receive do
      :release_blocking_llm -> [TildeTest.RuntimeEvents.completed("reply: #{prompt}")]
    after
      1_000 -> [TildeTest.RuntimeEvents.failed(:timeout)]
    end
  end
end

defmodule TildeTest.CancellableLLMBackend do
  @behaviour Tilde.Runtime.LLM.Provider

  @impl true
  def cancel_checkpoint(token, _opts) do
    test_pid = Application.fetch_env!(:tilde, :cancellable_llm_test_pid)
    send(test_pid, {:cancellable_llm_cancelled, token})
    {:ok, token}
  end

  @impl true
  def resume_checkpoint(_session, candidate, _opts) do
    [TildeTest.RuntimeEvents.completed("resumed: #{candidate.checkpoint_token}")]
  end

  @impl true
  def stream(_session, _opts) do
    test_pid = Application.fetch_env!(:tilde, :cancellable_llm_test_pid)
    {:ok, agent} = Agent.start_link(fn -> :running end)
    Process.link(agent)
    send(test_pid, {:cancellable_llm_started, self(), agent})

    Stream.concat(
      [
        TildeTest.RuntimeEvents.started(),
        TildeTest.RuntimeEvents.checkpoint("checkpoint-123"),
        TildeTest.RuntimeEvents.delta("working")
      ],
      blocking_stream()
    )
  end

  defp blocking_stream do
    Stream.resource(
      fn -> :ok end,
      fn
        :ok ->
          receive do
            :release_cancellable_llm -> {[TildeTest.RuntimeEvents.completed("released")], :done}
          after
            5_000 -> {[TildeTest.RuntimeEvents.failed(:timeout)], :done}
          end

        :done ->
          {:halt, :done}
      end,
      fn _state -> :ok end
    )
  end
end
