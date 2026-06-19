defmodule Tilde.Renderer.TextTest do
  use TildeTest.Case

  test "produces pi-like transcript snapshots" do
    transcript =
      [
        Tilde.user_message("Run tests", id: "evt_user"),
        Tilde.assistant_done("I'll run them.", id: "evt_assistant"),
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1"),
        Tilde.tool_stream("tool_1", :stdout, "ok\n"),
        Tilde.tool_done("tool_1")
      ]
      |> Transcript.from_events()

    assert Renderer.Text.render(transcript) ==
             """
             user
               Run tests

             assistant
               I'll run them.

             bash mix test success
             ok
             """
             |> String.trim_trailing()
  end
end
