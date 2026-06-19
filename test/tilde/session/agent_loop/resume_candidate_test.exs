defmodule Tilde.Session.AgentLoop.ResumeCandidateTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}
  alias Tilde.Session.AgentLoop.ResumeCandidate

  test "restored checkpoint runtime metadata produces a resume candidate" do
    session =
      Tilde.session(id: "resume-ready")
      |> Session.put_agent_runtime(%AgentRuntime{
        active?: true,
        input_index: 3,
        block_id: "msg_assistant_3",
        queue_length: 0,
        run_id: "run-1",
        request_id: "request-1",
        checkpoint_token: "checkpoint-1",
        iteration: 2
      })

    assert %ResumeCandidate{
             session_id: "resume-ready",
             input_index: 3,
             block_id: "msg_assistant_3",
             run_id: "run-1",
             request_id: "request-1",
             checkpoint_token: "checkpoint-1",
             iteration: 2
           } = ResumeCandidate.from_session(session)
  end

  test "missing token, run, or request id is not resumable" do
    refute resume_candidate(checkpoint_token: nil)
    refute resume_candidate(run_id: nil)
    refute resume_candidate(request_id: nil)
    refute resume_candidate(checkpoint_token: "")
  end

  test "live active assistant state is not resumable" do
    session =
      Tilde.session(id: "already-active")
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

    refute ResumeCandidate.from_session(session)
  end

  test "inactive runtime metadata is not resumable" do
    refute resume_candidate(active?: false)
  end

  defp resume_candidate(overrides) do
    attrs =
      Keyword.merge(
        [
          active?: true,
          input_index: 1,
          block_id: "msg_assistant_1",
          queue_length: 0,
          run_id: "run",
          request_id: "request",
          checkpoint_token: "checkpoint",
          iteration: 0
        ],
        overrides
      )

    Tilde.session(id: "resume-missing")
    |> Session.put_agent_runtime(AgentRuntime.new(attrs))
    |> ResumeCandidate.from_session()
  end
end
