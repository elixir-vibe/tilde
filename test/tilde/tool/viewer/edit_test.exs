defmodule Tilde.Tool.Viewer.EditTest do
  use TildeTest.Case

  alias Tilde.Core.Block
  alias Tilde.Tool.ViewModel

  test "renders final diff from typed result" do
    diff = "@@ -1 +1\n-old\n+new\n"

    view =
      Block.tool("tool_1", "edit", %{path: "lib/example.ex"})
      |> Block.finish_tool(:success, %{diff: diff})
      |> ViewModel.view()

    cell =
      Block.tool("tool_1", "edit", %{path: "lib/example.ex"})
      |> Block.finish_tool(:success, %{diff: diff})
      |> Tilde.Viewable.to_view()

    assert view.name == "edit"
    assert Enum.map(view.call_segments, & &1.text) == ["lib/example.ex"]
    assert view.lines == ["@@ -1 +1", "-old", "+new"]

    assert Enum.map(Enum.drop(cell.lines, 1), fn line -> hd(line.parts).style end) == [
             :muted,
             :error,
             :success
           ]
  end
end
