defmodule Tilde.Session.AgentLoop.ResumeStartTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}
  alias Tilde.Session.Server

  test "session server resumes restored checkpoint on startup" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.LLMBackend, fn ->
        {:ok, server} =
          Server.start_link(session: resumable_session("resume-start", "checkpoint-start"))

        session = wait_until_session(server, &assistant_source?(&1, "resumed: checkpoint-start"))

        assert latest_user_sources(session) == ["original prompt"]

        assert [
                 %Block{role: :user},
                 %Block{role: :assistant, source: "resumed: checkpoint-start"}
               ] =
                 session.transcript.blocks

        assert Session.agent_runtime(session).active? == false
      end)
    end)
  end

  test "resume failure appends public error, error lifecycle, and clears metadata" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.FailingLLMBackend, fn ->
        {:ok, server} =
          Server.start_link(session: resumable_session("resume-failed", "checkpoint-failed"))

        session = wait_until_session(server, &runtime_cleared?/1)

        assert_assistant_phase(session, :error)
        assert Session.agent_runtime(session).active? == false
        assert Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
      end)
    end)
  end

  test "resume cancellation appends cancelled lifecycle and clears metadata" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.CancelledLLMBackend, fn ->
        {:ok, server} =
          Server.start_link(
            session: resumable_session("resume-cancelled", "checkpoint-cancelled")
          )

        session = wait_until_session(server, &runtime_cleared?/1)

        assert_assistant_phase(session, :cancelled)
        assert Session.agent_runtime(session).active? == false
      end)
    end)
  end

  test "resume backend crashes map to failed lifecycle and clear metadata" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.CrashingLLMBackend, fn ->
        {:ok, server} =
          Server.start_link(session: resumable_session("resume-crash", "checkpoint-crash"))

        session = wait_until_session(server, &runtime_cleared?/1)

        assert_assistant_phase(session, :error)
        assert Session.agent_runtime(session).active? == false
        assert Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
      end)
    end)
  end

  test "session server does not resume restored checkpoint when LLM is disabled" do
    with_application_env(:llm_enabled, false, fn ->
      {:ok, server} = Server.start_link(session: resumable_session("resume-disabled", "token"))

      Process.sleep(50)

      session = Server.get_session(server)
      assert latest_user_sources(session) == ["original prompt"]
      refute Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
      assert Session.agent_runtime(session).active? == true
    end)
  end

  test "session server does not resume invalid checkpoint metadata" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.LLMBackend, fn ->
        session =
          resumable_session("resume-invalid", nil)
          |> Session.restore_metadata(%{agent_loop: %{active?: true}})

        {:ok, server} = Server.start_link(session: session)

        Process.sleep(50)

        session = Server.get_session(server)
        assert latest_user_sources(session) == ["original prompt"]
        refute Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
      end)
    end)
  end

  defp resumable_session(session_id, checkpoint_token) do
    Tilde.session(id: session_id)
    |> Session.append_event(Tilde.input_submitted("original prompt"))
    |> Session.put_agent_runtime(%AgentRuntime{
      active?: true,
      input_index: 1,
      block_id: "msg_assistant_2",
      queue_length: 0,
      run_id: "run",
      request_id: "request",
      checkpoint_token: checkpoint_token,
      iteration: 0
    })
  end

  defp wait_until_session(server, predicate, attempts \\ 20)

  defp wait_until_session(server, predicate, attempts) when attempts > 0 do
    session = Server.get_session(server)

    if predicate.(session) do
      session
    else
      Process.sleep(25)
      wait_until_session(server, predicate, attempts - 1)
    end
  end

  defp wait_until_session(server, _predicate, 0), do: Server.get_session(server)

  defp assistant_source?(%Session{} = session, source) do
    Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant, source: ^source}, &1))
  end

  defp runtime_cleared?(%Session{} = session), do: Session.agent_runtime(session).active? == false
end
