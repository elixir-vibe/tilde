defmodule Tilde.Tool.Viewer.ReadTest do
  use TildeTest.Case

  alias Tilde.Core.Block
  alias Tilde.Tool.ViewModel

  test "renders path ranges and hides content until expanded" do
    result = %{content: [%{type: "text", text: "one\ntwo\nthree\n"}]}

    tool =
      Block.tool("tool_1", "read", %{path: "lib/example.ex", offset: 2, limit: 2})
      |> Block.finish_tool(:success, result)

    compact = ViewModel.view(tool)
    expanded = tool |> Block.update_display(%{expanded?: true}) |> ViewModel.view()

    cell = Tilde.Viewable.to_view(tool)

    assert compact.name == "read"
    assert Enum.map(compact.call_segments, & &1.text) == ["lib/example.ex", ":2-3"]
    assert Enum.map(hd(cell.lines).parts, & &1.style) == [:title, :accent, :warning]
    assert compact.lines == []
    assert compact.hidden_lines == 3
    assert expanded.lines == ["one", "two", "three"]
  end
end
