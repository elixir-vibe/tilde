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

  test "tool view truncates compact output and ctrl-o display expands without mutating streams" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test"},
        display: %Display{compact_limit: {:lines, 2}}
      )
      |> Block.append_stream(:stdout, "one\ntwo\nthree\n")

    compact = ViewModel.view(tool)
    expanded = tool |> Block.update_display(%{expanded?: true}) |> ViewModel.view()

    assert compact.lines == ["two", "three"]
    assert [%{kind: :stdout, lines: ["two", "three"], hidden_lines: 1}] = compact.streams
    assert compact.hidden_lines == 1
    refute compact.expanded?

    assert expanded.lines == ["one", "two", "three"]
    assert [%{kind: :stdout, lines: ["one", "two", "three"], hidden_lines: 0}] = expanded.streams
    assert expanded.hidden_lines == 0
    assert expanded.expanded?
    assert tool.streams |> hd() |> Stream.text() == "one\ntwo\nthree\n"
  end

  test "fetch view keeps document-like compact output at the head" do
    tool =
      Block.tool("tool_1", "fetch", %{url: "https://example.test/large"},
        display: %Display{compact_limit: {:lines, 2}}
      )
      |> Block.append_stream(:stdout, "one\ntwo\nthree\n")

    compact = ViewModel.view(tool)

    assert compact.lines == ["one", "two"]
    assert [%{kind: :stdout, lines: ["one", "two"], hidden_lines: 1}] = compact.streams
    assert compact.hidden_lines == 1
  end

  test "runs represent styling without choosing a renderer" do
    run = Run.new("underlined", [:bold, :underline], %{href: "https://example.test"})

    assert run.text == "underlined"
    assert :bold in run.marks
    assert :underline in run.marks
    assert run.attrs.href == "https://example.test"
  end

  test "tool view preserves stream identity and metadata" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test", cwd: "/tmp/app"},
        display: %Display{compact_limit: {:lines, 2}},
        metadata: %{duration_ms: 42}
      )
      |> Block.append_stream(:stdout, "ok\n")
      |> Block.append_stream(:stderr, "warning\nmore\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    view = ViewModel.view(tool)

    assert view.metadata_rows == [cwd: "/tmp/app", exit: "0", duration: "42ms"]

    assert [stdout, stderr] = view.streams
    assert stdout.kind == :stdout
    assert stdout.lines == ["ok"]
    assert stdout.hidden_lines == 0
    assert stderr.kind == :stderr
    assert stderr.lines == ["more"]
    assert stderr.hidden_lines == 1
  end

  test "background tools render pi-style display labels" do
    view =
      Block.tool("tool_1", "background-start", %{name: "demo-server", command: "mix phx.server"})
      |> ViewModel.view()

    assert view.name == "bg start"
    assert Enum.map(view.call_segments, & &1.text) == ["demo-server", "→ mix phx.server"]
  end

  test "read tool renders path ranges and hides content until expanded" do
    result = %{content: [%{type: "text", text: "one\ntwo\nthree\n"}]}

    tool =
      Block.tool("tool_1", "read", %{path: "lib/example.ex", offset: 2, limit: 2})
      |> Block.finish_tool(:success, result)

    compact = ViewModel.view(tool)
    expanded = tool |> Block.update_display(%{expanded?: true}) |> ViewModel.view()

    assert compact.name == "read"
    assert Enum.map(compact.call_segments, & &1.text) == ["lib/example.ex:2-3"]
    assert compact.lines == []
    assert compact.hidden_lines == 3
    assert expanded.lines == ["one", "two", "three"]
  end

  test "edit tool renders final diff from typed result" do
    diff = "@@ -1 +1\n-old\n+new\n"

    view =
      Block.tool("tool_1", "edit", %{path: "lib/example.ex"})
      |> Block.finish_tool(:success, %{diff: diff})
      |> ViewModel.view()

    assert view.name == "edit"
    assert Enum.map(view.call_segments, & &1.text) == ["lib/example.ex"]
    assert view.lines == ["@@ -1 +1", "-old", "+new"]
  end
end
