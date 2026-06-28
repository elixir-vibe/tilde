defmodule Tilde.Runtime.EventTest do
  use TildeTest.Case

  alias Tilde.Runtime.Event

  test "normalizes atom and string keyed runtime event attributes" do
    assert %Event{
             seq: 7,
             run_id: "run",
             request_id: "request",
             iteration: 2,
             kind: :checkpoint,
             tool_call_id: "tool",
             llm_call_id: "llm",
             tool_name: "bash",
             data: %{token: "checkpoint"}
           } =
             Event.new(%{
               "seq" => 7,
               "run_id" => "run",
               "request_id" => "request",
               "iteration" => 2,
               "kind" => :checkpoint,
               "tool_call_id" => "tool",
               "llm_call_id" => "llm",
               "tool_name" => "bash",
               "data" => %{token: "checkpoint"}
             })
  end

  test "defaults optional fields for minimal runtime events" do
    assert %Event{seq: 0, kind: :request_failed, data: %{error: :boom}} =
             Event.new(kind: :request_failed, data: %{error: :boom})
  end
end
