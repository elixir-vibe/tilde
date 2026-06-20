defmodule Tilde.Tool.Viewer.ListTest do
  use TildeTest.Case

  alias Tilde.Core.{Block, Display}
  alias Tilde.Tool.ViewModel

  test "renders directory listing result content from first-party tool result" do
    result = %{
      content: [%{type: "text", text: "./ (4 of 4 entries)\nREADME.md\nlib/\ntest/\nmix.exs"}]
    }

    tool =
      Block.tool("tool_1", "list", %{path: "."}, display: %Display{compact_limit: {:lines, 3}})
      |> Block.finish_tool(:success, result)

    compact = ViewModel.view(tool)
    expanded = tool |> Block.update_display(%{expanded?: true}) |> ViewModel.view()

    assert [%{text: ".", color: :accent}] = compact.call_segments
    assert compact.lines == ["./ (4 of 4 entries)", "README.md", "lib/"]
    assert compact.hidden_lines == 2

    assert expanded.lines == ["./ (4 of 4 entries)", "README.md", "lib/", "test/", "mix.exs"]
    assert expanded.hidden_lines == 0
  end
end
