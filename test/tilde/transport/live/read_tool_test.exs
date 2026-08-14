defmodule Tilde.Transport.Live.ReadToolTest do
  use TildeTest.Case

  test "expanded read tool syntax highlights through Lumis" do
    result = %{content: [%{type: "text", text: "def hello, do: :world\n"}]}

    tool =
      Block.tool("read_1", "read", %{path: "lib/example.ex"})
      |> Block.finish_tool(:success, result)
      |> Block.update_display(%{expanded?: true})

    html =
      render_component(&Tilde.Transport.Live.ViewRenderer.cell/1,
        cell: Tilde.Viewable.to_view(tool)
      )

    assert html =~ ~s|class="lumis"|
    assert html =~ ~s|class="language-elixir"|
    assert html =~ "var(--syntax-keyword)"
    assert html =~ "var(--syntax-function)"
    assert html =~ "var(--syntax-punctuation)"
    assert html =~ "var(--syntax-constant)"
  end
end
