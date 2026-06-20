defmodule Tilde.Tool.Viewer.BashTest do
  use TildeTest.Case

  alias Tilde.Core.{Block, Display}
  alias Tilde.Tool.ViewModel

  test "renders bash result content when no stream chunks were recorded" do
    result = %{
      content: [%{type: "text", text: "one\ntwo\nthree\n"}],
      exit_code: 0,
      duration_ms: 4
    }

    tool =
      Block.tool("tool_1", "bash", %{command: "printf 'one\\ntwo\\nthree\\n'"},
        display: %Display{compact_limit: {:lines, 2}}
      )
      |> Block.finish_tool(:success, result)

    compact = ViewModel.view(tool)
    expanded = tool |> Block.update_display(%{expanded?: true}) |> ViewModel.view()

    assert compact.lines == ["two", "three"]
    assert compact.hidden_lines == 1
    assert compact.status == :success

    assert expanded.lines == ["one", "two", "three"]
    assert expanded.hidden_lines == 0
  end
end
