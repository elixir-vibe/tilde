defmodule Tilde.Renderer.TUI.Palette do
  @moduledoc "Terminal renderer for the shared command palette state."

  alias Tilde.Core.Palette
  alias Tilde.Core.Palette.Item
  alias Tilde.Renderer.TUI.Theme

  @doc "Renders an open palette as a terminal dialog."
  @spec render(Palette.t(), pos_integer(), keyword()) :: String.t()
  def render(palette, width, opts \\ [])

  def render(%Palette{open?: false}, _width, _opts), do: ""

  def render(%Palette{} = palette, width, opts) do
    inner_width = max(min(width - 4, 72), 20)
    title = " " <> title(palette) <> " "
    query = "> " <> palette.query

    lines =
      [modes(palette), query, ""] ++
        item_lines(palette) ++
        ["", Theme.muted("enter open · esc close", opts)]

    top =
      "╭" <> title <> String.duplicate("─", max(inner_width + 2 - String.length(title), 0)) <> "╮"

    bottom = "╰" <> String.duplicate("─", inner_width + 2) <> "╯"

    ([top] ++ Enum.map(lines, &dialog_line(&1, inner_width)) ++ [bottom])
    |> Enum.map_join("\n", &Theme.cell(&1, opts))
  end

  defp title(%Palette{mode: :symbols}), do: "jump to symbol"
  defp title(%Palette{}), do: "open file"

  defp modes(%Palette{mode: :symbols}), do: "  files  [symbols]"
  defp modes(%Palette{}), do: " [files]  symbols"

  defp item_lines(%Palette{mode: :symbols, items: []}), do: ["  No matching symbols."]
  defp item_lines(%Palette{items: []}), do: ["  No matching files."]

  defp item_lines(%Palette{} = palette) do
    palette.items
    |> Enum.take(8)
    |> Enum.with_index()
    |> Enum.map(fn {%Item{} = item, index} ->
      marker = if index == palette.selected_index, do: "›", else: " "
      "#{marker} #{item.label}  #{item.detail || ""}"
    end)
  end

  defp dialog_line(line, width), do: "│ " <> pad(truncate(line, width), width) <> " │"

  defp pad(line, width), do: line <> String.duplicate(" ", max(width - String.length(line), 0))

  defp truncate(line, width) do
    if String.length(line) <= width do
      line
    else
      String.slice(line, 0, max(width - 1, 0)) <> "…"
    end
  end
end
