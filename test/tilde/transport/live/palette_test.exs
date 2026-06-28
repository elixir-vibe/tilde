defmodule Tilde.Transport.Live.PaletteTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Palette
  alias Tilde.Core.Palette.Item

  test "renders an open file palette as a dialog" do
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

    html = render_component(&Tilde.Transport.Live.Palette.palette/1, palette: palette)

    assert html =~ ~s|id="tilde-palette"|
    assert html =~ ~s|role="dialog"|
    assert html =~ "open file"
    assert html =~ ~s|aria-label="palette modes"|
    assert html =~ ~s|phx-click="tilde:palette:mode"|
    assert html =~ ~s|phx-value-mode="symbols"|
    assert html =~ ~s|<kbd class="key">f</kbd>|
    assert html =~ ~s|<span class="label">files</span>|
    assert html =~ ~s|<kbd class="key">s</kbd>|
    assert html =~ ~s|<span class="label">symbols</span>|
    assert html =~ ~s|phx-change="tilde:palette:change"|
    assert html =~ ~s|phx-submit="tilde:palette:accept"|
    assert html =~ ~s|phx-hook="TildePaletteInput"|
    assert html =~ ~s|value="work"|
    assert html =~ "app.css"
    assert html =~ "assets/css/app.css"
    assert html =~ ~s|class="choice selected"|
    assert html =~ ~s|phx-click="tilde:palette:select"|
    assert html =~ ~s|phx-value-index="1"|
  end

  test "renders symbol palette mode" do
    palette =
      Palette.new(
        open?: true,
        mode: :symbols,
        items: [
          Item.new(
            id: "symbol:a:1:def run/1",
            label: "def run/1",
            detail: "function · line 12",
            kind: :symbol,
            action: %{type: :jump_symbol, line: 12}
          )
        ]
      )

    html = render_component(&Tilde.Transport.Live.Palette.palette/1, palette: palette)

    assert html =~ "jump to symbol"
    assert html =~ "def run/1"
    assert html =~ "function · line 12"
    assert html =~ ~s|class="action selected"|
  end

  test "does not render when closed" do
    html = render_component(&Tilde.Transport.Live.Palette.palette/1, palette: Palette.new())

    assert html == ""
  end
end
