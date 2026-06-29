defmodule Tilde.Runtime.JidokaEventTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.AgentRuntime
  alias Tilde.Runtime.JidokaEvent
  alias Tilde.Tool.Event, as: ToolEvent

  test "projects content and thinking deltas" do
    assert JidokaEvent.delta(TildeTest.RuntimeEvents.delta("hello")) == {:content, "hello"}
    assert JidokaEvent.delta(TildeTest.RuntimeEvents.thinking_delta("hmm")) == {:thinking, "hmm"}
    assert JidokaEvent.delta(TildeTest.RuntimeEvents.delta("")) == nil
  end

  test "projects operation start events" do
    assert %ToolEvent{
             id: "tool-1",
             name: "utc_now",
             args: %{timezone: "UTC"},
             status: :running,
             phase: :started
           } =
             TildeTest.RuntimeEvents.tool_started("tool-1", "utc_now", %{timezone: "UTC"})
             |> JidokaEvent.operation_started()
  end

  test "projects operation terminal events" do
    assert %ToolEvent{
             id: "tool-1",
             output: "done",
             status: :success,
             phase: :finished
           } =
             TildeTest.RuntimeEvents.tool_completed("tool-1", "utc_now", "done")
             |> JidokaEvent.operation_finished()

    assert %ToolEvent{output: %{error: :boom}, status: :error} =
             operation_event(:effect_failed, %{error: {:error, :boom}}, effect_id: "tool-2")
             |> JidokaEvent.operation_finished()
  end

  test "projects terminal text, cancellation, and failure reasons" do
    assert JidokaEvent.terminal_text(TildeTest.RuntimeEvents.completed("answer")) == "answer"
    assert JidokaEvent.cancelled?(TildeTest.RuntimeEvents.failed(:cancelled))
    refute JidokaEvent.cancelled?(TildeTest.RuntimeEvents.failed(:boom))
    assert JidokaEvent.failure_reason(TildeTest.RuntimeEvents.failed(:boom)) == :boom
  end

  test "projects sanitized terminal metadata" do
    runtime = %AgentRuntime{
      active?: true,
      run_id: "tilde",
      request_id: "request",
      checkpoint_token: "checkpoint",
      iteration: 3
    }

    event =
      TildeTest.RuntimeEvents.completed("answer", %{
        usage: %{input_tokens: 1, output_tokens: 2},
        termination_reason: :final_answer,
        reasoning_details: [%{summary: "ok", dropped: self()}],
        jidoka: %{metadata: %{generated_at: ~U[2026-06-29 10:00:00Z], callback: fn -> :bad end}}
      })

    assert %{
             run_id: "tilde",
             request_id: "request",
             checkpoint_token: "checkpoint",
             iteration: 3,
             usage: %{input_tokens: 1, output_tokens: 2},
             termination_reason: :final_answer,
             reasoning_details: [%{summary: "ok"}],
             jidoka: %{metadata: %{generated_at: generated_at}}
           } = JidokaEvent.terminal_metadata(runtime, event)

    assert generated_at == inspect(~U[2026-06-29 10:00:00Z])
  end

  defp operation_event(kind, data, opts) do
    Jidoka.Event.build(kind, [],
      seq: System.unique_integer([:positive]),
      agent_id: "test-run",
      request_id: "test-request",
      loop_index: 0,
      effect_id: Keyword.get(opts, :effect_id),
      effect_kind: :operation,
      operation: Keyword.get(opts, :operation, "tool"),
      data: data
    )
  end
end
