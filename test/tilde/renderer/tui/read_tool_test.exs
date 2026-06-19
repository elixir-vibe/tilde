defmodule Tilde.Renderer.TUI.ReadToolTest do
  use TildeTest.Case

  test "expanded read tool syntax highlights through Lumis terminal formatter" do
    result = %{content: [%{type: "text", text: "def hello, do: :world\n"}]}

    rendered =
      Block.tool("read_1", "read", %{path: "lib/example.ex"})
      |> Block.finish_tool(:success, result)
      |> Block.update_display(%{expanded?: true})
      |> Tilde.Viewable.to_view()
      |> Tilde.Renderer.TUI.ViewRenderer.render(80, ansi: true)

    assert rendered =~ "\e["
    assert strip_ansi(rendered) =~ "def hello, do: :world"
  end
end
