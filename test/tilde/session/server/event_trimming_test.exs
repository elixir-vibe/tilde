defmodule Tilde.Session.Server.EventTrimmingTest do
  use TildeTest.Case

  test "applies configured event trimming" do
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
        assert Enum.map(updated.transcript.blocks, & &1.source) == ["two", "three"]

        GenServer.stop(pid)
      end)
    end)
  end
end
