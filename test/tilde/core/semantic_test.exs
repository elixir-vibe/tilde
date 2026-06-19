defmodule Tilde.CoreSemanticTest do
  use TildeTest.Case

  doctest Tilde

  test "reduces message and tool events into semantic blocks" do
    events = [
      Tilde.user_message("Run tests", id: "evt_user"),
      Tilde.assistant_delta("I'll run ", id: "evt_assistant", block_id: "msg_assistant"),
      Tilde.assistant_delta("them.", id: "evt_assistant_2", block_id: "msg_assistant"),
      Tilde.tool_started("bash", %{command: "mix test"}, id: "evt_tool", tool_call_id: "tool_1"),
      Tilde.tool_stream("tool_1", :stdout, "Compiling...\n"),
      Tilde.tool_stream("tool_1", :stdout, "2 tests, 0 failures\n"),
      Tilde.tool_done("tool_1", :success, %{exit_code: 0})
    ]

    transcript = Tilde.transcript(events)

    assert [user, assistant, tool] = transcript.blocks
    assert user.role == :user
    assert user.source == "Run tests"
    assert assistant.source == "I'll run them."
    assert tool.kind == :tool
    assert tool.name == "bash"
    assert tool.status == :success
    assert [%Stream{kind: :stdout} = stdout] = tool.streams
    assert Stream.lines(stdout) == ["Compiling...", "2 tests, 0 failures"]
    assert tool.result == %{exit_code: 0}
  end

  test "runs represent styling without choosing a renderer" do
    run = Run.new("underlined", [:bold, :underline], %{href: "https://example.test"})

    assert run.text == "underlined"
    assert :bold in run.marks
    assert :underline in run.marks
    assert run.attrs.href == "https://example.test"
  end
end
