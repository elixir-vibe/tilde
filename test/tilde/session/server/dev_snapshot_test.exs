defmodule Tilde.Session.Server.DevSnapshotTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}
  alias Tilde.Session.AgentLoop.ResumeCandidate
  alias Tilde.Session.Server

  test "dev snapshot includes resume candidate for restored checkpoint metadata" do
    session =
      Tilde.session(id: "snapshot-resume")
      |> Session.put_agent_runtime(%AgentRuntime{
        active?: true,
        input_index: 4,
        block_id: "msg_assistant_4",
        queue_length: 0,
        run_id: "run-4",
        request_id: "request-4",
        checkpoint_token: "checkpoint-4",
        iteration: 3
      })

    {:ok, server} = Server.start_link(session: session)

    assert %{
             resume_candidate: %ResumeCandidate{
               session_id: "snapshot-resume",
               input_index: 4,
               block_id: "msg_assistant_4",
               run_id: "run-4",
               request_id: "request-4",
               checkpoint_token: "checkpoint-4",
               iteration: 3
             }
           } = Server.dev_snapshot(server)
  end

  test "dev snapshot suppresses resume candidate while assistant is active" do
    session =
      Tilde.session(id: "snapshot-active")
      |> Session.append_event(Tilde.assistant_turn_started(block_id: "msg_assistant_2"))
      |> Session.put_agent_runtime(%AgentRuntime{
        active?: true,
        input_index: 2,
        block_id: "msg_assistant_2",
        queue_length: 0,
        run_id: "run-2",
        request_id: "request-2",
        checkpoint_token: "checkpoint-2",
        iteration: 1
      })

    {:ok, server} = Server.start_link(session: session)

    assert %{resume_candidate: nil} = Server.dev_snapshot(server)
  end
end
