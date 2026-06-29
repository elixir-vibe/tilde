defmodule Tilde.Core.AgentRuntimeTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}

  test "loads string-keyed persisted runtime metadata into typed contract" do
    runtime =
      AgentRuntime.load(%{
        "active?" => true,
        "input_index" => 7,
        "block_id" => "msg_assistant_7",
        "queue_length" => 2,
        "run_id" => "run-1",
        "request_id" => "request-1",
        "checkpoint_token" => "checkpoint-1",
        "iteration" => 3
      })

    assert %AgentRuntime{
             active?: true,
             input_index: 7,
             block_id: "msg_assistant_7",
             queue_length: 2,
             run_id: "run-1",
             request_id: "request-1",
             checkpoint_token: "checkpoint-1",
             iteration: 3
           } = runtime
  end

  test "detects resumable runtime metadata" do
    runtime = %AgentRuntime{
      active?: true,
      run_id: "run",
      request_id: "request",
      checkpoint_token: "checkpoint"
    }

    assert AgentRuntime.resumable?(runtime)
    refute AgentRuntime.resumable?(%{runtime | active?: false})
    refute AgentRuntime.resumable?(%{runtime | run_id: nil})
    refute AgentRuntime.resumable?(%{runtime | request_id: nil})
    refute AgentRuntime.resumable?(%{runtime | checkpoint_token: ""})
  end

  test "restores session metadata to canonical agent runtime dump" do
    session =
      Tilde.session(id: "metadata")
      |> Session.restore_metadata(%{
        "title" => "Restored",
        "agent_loop" => %{
          "active?" => true,
          "input_index" => 4,
          "block_id" => "msg_assistant_4",
          "queue_length" => 1,
          "run_id" => "run-2",
          "request_id" => "request-2",
          "checkpoint_token" => "checkpoint-2",
          "iteration" => 5
        }
      })

    assert session.metadata["title"] == "Restored"
    refute Map.has_key?(session.metadata, "agent_loop")

    assert session.metadata[:agent_loop] ==
             AgentRuntime.dump(%AgentRuntime{
               active?: true,
               input_index: 4,
               block_id: "msg_assistant_4",
               queue_length: 1,
               run_id: "run-2",
               request_id: "request-2",
               checkpoint_token: "checkpoint-2",
               iteration: 5
             })

    assert %AgentRuntime{checkpoint_token: "checkpoint-2"} = Session.agent_runtime(session)
  end
end
