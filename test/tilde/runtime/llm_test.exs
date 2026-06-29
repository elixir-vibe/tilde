defmodule Tilde.Runtime.LLMTest do
  use TildeTest.Case

  alias Tilde.Runtime.LLM

  test "builds Jidoka failure events for runtime boundary failures" do
    assert %Jidoka.Event{
             event: :turn_failed,
             status: :failed,
             agent_id: "tilde-test",
             request_id: "tilde-test",
             loop_index: 2,
             data: %{error: :boom}
           } = LLM.failed_event(:boom, source: "tilde-test", iteration: 2)
  end
end
