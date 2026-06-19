defmodule Tilde.Tool.Viewer.FetchTest do
  use TildeTest.Case

  alias Tilde.Core.{Block, Display}
  alias Tilde.Tool.ViewModel

  test "keeps document-like compact output at the head" do
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
end
