defmodule Tilde.Session.AgentLoop.ResumeStartTest do
  use TildeTest.Case

  alias Tilde.Core.{AgentRuntime, Session}
  alias Tilde.Session.Server

  test "session server resumes restored checkpoint on startup" do
    with_application_env(:llm_enabled, true, fn ->
      {session, llm_opts} = resumable_session("resume-start", final_llm("resumed from snapshot"))

      {:ok, server} = Server.start_link(session: session, llm_opts: llm_opts)

      session = wait_until_session(server, &assistant_source?(&1, "resumed from snapshot"))

      assert latest_user_sources(session) == ["original prompt"]

      assert [
               %Block{role: :user},
               %Block{role: :assistant, source: "resumed from snapshot"}
             ] = session.transcript.blocks

      assert Session.agent_runtime(session).active? == false
    end)
  end

  test "resume failure appends public error, error lifecycle, and clears metadata" do
    with_application_env(:llm_enabled, true, fn ->
      {session, _llm_opts} = resumable_session("resume-failed", final_llm("ignored"))

      {:ok, server} =
        Server.start_link(
          session: session,
          llm_opts: [
            llm: fn _intent, _journal -> {:error, :boom} end,
            stream_event_timeout_ms: 10
          ]
        )

      session = wait_until_session(server, &runtime_cleared?/1)

      assert_assistant_phase(session, :error)
      assert Session.agent_runtime(session).active? == false
      assert Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
    end)
  end

  test "resume cancelled Jidoka capability appends error lifecycle and clears metadata" do
    with_application_env(:llm_enabled, true, fn ->
      {session, _llm_opts} = resumable_session("resume-cancelled", final_llm("ignored"))

      {:ok, server} =
        Server.start_link(
          session: session,
          llm_opts: [
            llm: fn _intent, _journal -> {:error, :cancelled} end,
            stream_event_timeout_ms: 10
          ]
        )

      session = wait_until_session(server, &runtime_cleared?/1)

      assert_assistant_phase(session, :error)
      assert Session.agent_runtime(session).active? == false
    end)
  end

  test "resume runtime crashes map to failed lifecycle and clear metadata" do
    with_application_env(:llm_enabled, true, fn ->
      {session, _llm_opts} = resumable_session("resume-crash", final_llm("ignored"))

      {:ok, server} =
        Server.start_link(
          session: session,
          llm_opts: [llm: fn _intent, _journal -> raise "boom" end, stream_event_timeout_ms: 10]
        )

      session = wait_until_session(server, &runtime_cleared?/1)

      assert_assistant_phase(session, :error)
      assert Session.agent_runtime(session).active? == false
      assert Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
    end)
  end

  test "session server does not resume restored checkpoint when LLM is disabled" do
    with_application_env(:llm_enabled, false, fn ->
      {session, _llm_opts} = resumable_session("resume-disabled", final_llm("ignored"))
      {:ok, server} = Server.start_link(session: session)

      Process.sleep(50)

      session = Server.get_session(server)
      assert latest_user_sources(session) == ["original prompt"]
      refute Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
      assert Session.agent_runtime(session).active? == true
    end)
  end

  test "session server does not resume invalid checkpoint metadata" do
    with_application_env(:llm_enabled, true, fn ->
      {session, _llm_opts} = resumable_session("resume-invalid", final_llm("ignored"))

      session =
        session
        |> Session.put_agent_runtime(%AgentRuntime{
          active?: true,
          input_index: 1,
          block_id: "msg_assistant_2",
          queue_length: 0,
          run_id: nil,
          request_id: nil,
          checkpoint_token: nil,
          iteration: nil
        })

      {:ok, server} = Server.start_link(session: session)

      Process.sleep(50)

      session = Server.get_session(server)
      assert latest_user_sources(session) == ["original prompt"]
      refute Enum.any?(session.transcript.blocks, &match?(%Block{role: :assistant}, &1))
    end)
  end

  defp resumable_session(session_id, resume_llm) do
    source_session =
      Tilde.session(id: session_id)
      |> Session.append_event(Tilde.input_submitted("original prompt"))

    {snapshot, request_id} = hibernated_snapshot(source_session)

    session =
      source_session
      |> Session.put_agent_runtime(%AgentRuntime{
        active?: true,
        input_index: 1,
        block_id: "msg_assistant_2",
        queue_length: 0,
        run_id: "tilde",
        request_id: request_id,
        checkpoint_token: snapshot,
        iteration: 0
      })

    {session, [llm: resume_llm]}
  end

  defp hibernated_snapshot(session) do
    events =
      session
      |> Tilde.Runtime.LLM.Jidoka.stream(
        checkpoint: :before_each_effect,
        llm: final_llm("ignored before resume")
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
