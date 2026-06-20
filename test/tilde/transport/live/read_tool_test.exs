defmodule Tilde.Transport.Live.ReadToolTest do
  use TildeTest.Case

  test "expanded read tool syntax highlights through Lumis" do
    result = %{content: [%{type: "text", text: "def hello, do: :world\n"}]}

    tool =
      Block.tool("read_1", "read", %{path: "lib/example.ex"})
      |> Block.finish_tool(:success, result)
      |> Block.update_display(%{expanded?: true})

    html = render_component(&Tilde.Transport.Live.Tool.tool/1, block: tool)

    assert html =~ ~s|class="lumis"|
    assert html =~ ~s|class="language-elixir"|
    assert html =~ "var(--color-link)"
    assert html =~ "var(--color-muted)"
    assert html =~ "var(--color-warning)"
    refute html =~ "var(--color-success)"
    refute html =~ "github_light"
  end
end
