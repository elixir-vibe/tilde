defmodule Tilde.Renderer.TUI.PaletteTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Palette
  alias Tilde.Core.Palette.Item
  alias Tilde.Renderer.TUI.Palette, as: PaletteRenderer

  test "renders an open palette as a terminal dialog" do
    palette =
      Palette.new(
        open?: true,
        query: "work",
        selected_index: 1,
        items: [
          Item.new(id: "file:a", label: "app.css", detail: "assets/css/app.css"),
          Item.new(id: "file:w", label: "workspace.ex", detail: "lib/tilde/workspace.ex")
        ]
      )

    rendered = PaletteRenderer.render(palette, 64, ansi: false)

    assert rendered =~ "╭ open file "
    assert rendered =~ "[files]  symbols"
    assert rendered =~ "> work"
    assert rendered =~ "  app.css  assets/css/app.css"
    assert rendered =~ "› workspace.ex  lib/tilde/workspace.ex"
    assert rendered =~ "enter open · esc close"
  end

  test "renders symbol mode" do
    palette =
      Palette.new(
        open?: true,
        mode: :symbols,
        items: [
          Item.new(
            id: "symbol:a",
            label: "def run/1",
            detail: "function · line 12",
            kind: :symbol
          )
        ]
      )

    rendered = PaletteRenderer.render(palette, 64, ansi: false)

    assert rendered =~ "╭ jump to symbol "
    assert rendered =~ "files  [symbols]"
    assert rendered =~ "› def run/1  function · line 12"
  end

  test "closed palette renders nothing" do
    assert PaletteRenderer.render(Palette.new(), 64, ansi: false) == ""
  end
end
