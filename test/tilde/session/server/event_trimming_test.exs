defmodule Tilde.Session.Server.EventTrimmingTest do
  use TildeTest.Case

  test "starts the agent loop when a submitted input replaces a trimmed event" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.StreamingLLMBackend, fn ->
        with_application_env(:session_event_limit, 6, fn ->
          name =
            :"tilde_session_server_trimmed_llm_start_test_#{System.unique_integer([:positive])}"

          session =
            Tilde.session(id: "trimmed_llm_start")
            |> Session.append_events([
              Tilde.user_message("old one"),
              Tilde.assistant_done("old two"),
              Tilde.user_message("old three"),
              Tilde.assistant_done("old four"),
              Tilde.user_message("old five"),
              Tilde.assistant_done("old six")
            ])

          assert [_, _, _, _, _, _] = session.events

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: session
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)

          Tilde.Session.Server.append_event(name, Tilde.input_submitted("new prompt"))

          assert_receive {:tilde_session_updated, "trimmed_llm_start",
                          %Session{assistant: %{phase: :waiting}}}

          assert_eventually(fn ->
            receive do
              {:tilde_session_updated, "trimmed_llm_start",
               %Session{transcript: %{blocks: blocks}}} ->
                Enum.any?(blocks, &(&1.source == "old one")) and
                  Enum.any?(blocks, &(&1.role == :assistant and &1.source == "hello"))
            after
              10 ->
                false
            end
          end)

          GenServer.stop(pid)
        end)
      end)
    end)
  end

  test "applies configured event trimming without hiding rendered blocks" do
    with_application_env(:llm_enabled, false, fn ->
      with_application_env(:session_event_limit, 2, fn ->
        name = :"tilde_session_server_trim_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "trim_test")
                 )

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("one"))
        Tilde.Session.Server.append_event(name, Tilde.assistant_done("two"))
        updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("three"))

        assert Enum.map(updated.events, & &1.text) == ["two", "three"]
        assert Enum.map(updated.transcript.blocks, & &1.source) == ["one", "two", "three"]

        GenServer.stop(pid)
      end)
    end)
  end

  defp assert_eventually(fun, attempts \\ 50)
  defp assert_eventually(_fun, 0), do: flunk("condition was not met")

  defp assert_eventually(fun, attempts) when is_function(fun, 0) do
    if fun.() do
      assert true
    else
      Process.sleep(10)
      assert_eventually(fun, attempts - 1)
    end
  end
end
