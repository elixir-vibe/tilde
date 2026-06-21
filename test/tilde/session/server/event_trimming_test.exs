defmodule Tilde.Session.Server.EventTrimmingTest do
  use TildeTest.Case

  test "session server keeps visible and raw history" do
    with_application_env(:llm_enabled, false, fn ->
      name = :"tilde_session_server_history_test_#{System.unique_integer([:positive])}"

      assert {:ok, pid} =
               Tilde.Session.Server.start_link(
                 name: name,
                 session: Tilde.session(id: "history_test")
               )

      Tilde.Session.Server.append_event(name, Tilde.input_submitted("one"))
      Tilde.Session.Server.append_event(name, Tilde.assistant_done("two"))
      updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("three"))

      assert Enum.map(updated.events, & &1.text) == ["one", "two", "three"]
      assert Enum.map(updated.transcript.blocks, & &1.source) == ["one", "two", "three"]

      GenServer.stop(pid)
    end)
  end
end
