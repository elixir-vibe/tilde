defmodule Tilde.Runtime.LLM.ResumeTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}
  alias Tilde.Runtime.LLM

  test "facade resumes a Jidoka snapshot with an injected fake LLM" do
    session = Tilde.session(id: "resume-facade")

    {snapshot, request_id} = hibernated_snapshot(session)

    runtime = %AgentRuntime{
      active?: true,
      input_index: 1,
      block_id: "msg_assistant_1",
      queue_length: 0,
      run_id: "tilde",
      request_id: request_id,
      checkpoint_token: snapshot,
      iteration: 0
    }

    assert [%Jidoka.Event{event: :turn_finished, data: %{result: result}}] =
             session
             |> LLM.resume_checkpoint(runtime, llm: final_llm("resumed through Jidoka"))
             |> Enum.filter(&(&1.event == :turn_finished))

    assert result == "resumed through Jidoka"
  end

  test "Jidoka runtime reports missing OpenRouter key before resuming runtime" do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.delete_env("OPENROUTER_API_KEY")

    session = resume_session("resume-jidoka", "checkpoint-jidoka")
    runtime = Session.agent_runtime(session)

    assert [
             %Jidoka.Event{
               event: :turn_failed,
               data: %{error: :missing_openrouter_api_key}
             }
           ] =
             session
             |> Tilde.Runtime.LLM.Jidoka.resume_checkpoint(runtime)
             |> Enum.to_list()

    restore_system_env("OPENROUTER_API_KEY", previous)
  end

  defp hibernated_snapshot(session) do
    events =
      session
      |> Session.append_event(Tilde.input_submitted("pause before final"))
      |> Tilde.Runtime.LLM.Jidoka.stream(
        checkpoint: :before_each_effect,
        llm: final_llm("ignored until resume")
      )
      |> Enum.to_list()

    assert %Jidoka.Event{event: :turn_hibernated, data: %{snapshot: snapshot}} =
             hibernated =
             List.last(events)

    {snapshot, hibernated.request_id}
  end

  defp final_llm(content) do
    fn _intent, _journal ->
      {:ok, Jidoka.Effect.LLMDecision.final(content)}
    end
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
