defmodule Tilde.Tool.Viewer.DefaultTest do
  use TildeTest.Case

  alias Tilde.Core.{Block, Display, Stream}
  alias Tilde.Tool.ViewModel

  test "truncates compact output and ctrl-o display expands without mutating streams" do
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

  test "preserves stream identity and metadata" do
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
end
