defmodule Tilde.Transport.Live.MarkdownTest do
  use TildeTest.Case

  test "thematic breaks use three dimmed lines" do
    block = Block.message("msg_1", :assistant, "Before\n\n---\n\nAfter")

    html =
      render_component(&Tilde.Transport.Live.ViewRenderer.cell/1,
        cell: Tilde.Viewable.to_view(block)
      )

    css = asset_css("components/markdown.css")

    assert html =~ "<hr"
    assert css =~ ".tilde .markdown hr"
    assert css =~ "height: 3lh"
    assert css =~ "color: var(--color-muted)"
    assert css =~ "0 2.5lh / 100% 1px no-repeat"
  end

  test "tables remain semantic HTML with terminal-like styling" do
    block =
      Block.message("msg_1", :assistant, "| name | status |\n| --- | --- |\n| LiveView | ok |")

    html =
      render_component(&Tilde.Transport.Live.ViewRenderer.cell/1,
        cell: Tilde.Viewable.to_view(block)
      )

    css = asset_css("components/markdown.css")

    assert html =~ "<table>"
    assert html =~ "<th>name</th>"
    assert html =~ "<td>LiveView</td>"
    assert css =~ ".tilde .markdown table"
    assert css =~ "padding: 0 var(--space-cell)"
    assert css =~ "border: 1px solid var(--color-border)"
  end
end
