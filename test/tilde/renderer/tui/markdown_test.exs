defmodule Tilde.Renderer.TUI.MarkdownTest do
  use TildeTest.Case

  test "tables render as ASCII grids from MDEx AST" do
    markdown = """
    Before

    | surface | renderer |
    | --- | ---: |
    | web | LiveView DOM |
    | ssh | semantic TUI |

    After
    """

    lines = Tilde.Renderer.TUI.Markdown.render_lines(markdown)

    assert "Before" in lines
    assert "┌─────────┬──────────────┐" in lines
    assert "│ surface │     renderer │" in lines
    assert "│ web     │ LiveView DOM │" in lines
    assert "│ ssh     │ semantic TUI │" in lines
    assert "└─────────┴──────────────┘" in lines
    assert "After" in lines
  end

  test "thematic breaks render as three dimmed lines" do
    lines = Tilde.Renderer.TUI.Markdown.render_lines("Before\n\n---\n\nAfter", 8, ansi: false)

    assert lines == [
             "Before",
             "────────",
             "────────",
             "────────",
             "After"
           ]

    ansi_lines = Tilde.Renderer.TUI.Markdown.render_lines("---", 3, ansi: true)
    assert [_, _, _] = ansi_lines
    assert Enum.all?(ansi_lines, &String.contains?(&1, IO.ANSI.faint()))
  end
end
