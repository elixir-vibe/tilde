defmodule Tilde.Runtime.LLM.ResumeTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}
  alias Tilde.Runtime.LLM
  alias Tilde.Session.AgentLoop.ResumeCandidate

  test "facade delegates checkpoint resume to configured backend" do
    session = resume_session("resume-facade", "checkpoint-facade")
    candidate = ResumeCandidate.from_session(session)

    assert [%Jidoka.Event{event: :turn_finished, data: %{result: result}}] =
             session
             |> LLM.resume_checkpoint(candidate, backend: TildeTest.LLMBackend)
             |> Enum.to_list()

    assert result == "resumed: checkpoint-facade"
  end

  test "jido provider reports missing OpenRouter key before resuming runtime" do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.delete_env("OPENROUTER_API_KEY")

    session = resume_session("resume-jido", "checkpoint-jido")
    candidate = ResumeCandidate.from_session(session)

    assert [
             %Jidoka.Event{
               event: :turn_failed,
               data: %{error: :missing_openrouter_api_key}
             }
           ] =
             session
             |> Tilde.Runtime.LLM.Provider.Jido.resume_checkpoint(candidate)
             |> Enum.to_list()

    restore_system_env("OPENROUTER_API_KEY", previous)
  end

  defp resume_session(session_id, checkpoint_token) do
    Tilde.session(id: session_id)
    |> Session.put_agent_runtime(%AgentRuntime{
      active?: true,
      input_index: 1,
      block_id: "msg_assistant_1",
      queue_length: 0,
      run_id: "run",
      request_id: "request",
      checkpoint_token: checkpoint_token,
      iteration: 0
    })
  end
end
