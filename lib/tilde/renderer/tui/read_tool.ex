defmodule Tilde.Renderer.TUI.ReadTool do
  @moduledoc "TUI projection for expanded read tool content."

  alias Tilde.Renderer.SyntaxHighlight
  alias Tilde.Renderer.TUI.{TextLayout, Theme}
  alias Tilde.Tool.View.Read
  alias Tilde.View.{Cell, Helpers, Line, Text}

  @spec render(Cell.t(), pos_integer(), keyword()) :: [String.t()]
  def render(%Cell{attrs: %{view: view}} = cell, width, opts) do
    inner_width = max(width - cell.padding_x * 2, 1)
    [header | rest] = cell.lines
    footer = List.last(rest)

    List.duplicate("", cell.padding_y) ++
      [render_line(header, inner_width, cell, opts)] ++
      highlighted_lines(view, inner_width, cell, opts) ++
      [render_line(footer, inner_width, cell, opts)] ++
      List.duplicate("", cell.padding_y)
  end

  defp highlighted_lines(view, inner_width, cell, opts) do
    view
    |> Read.source()
    |> SyntaxHighlight.to_terminal(Read.path(view))
    |> String.trim_trailing()
    |> String.split("\n", trim: false)
    |> Enum.map(&render_ansi_line(&1, inner_width, cell, opts))
  end

  defp render_line(line, inner_width, cell, opts) do
    styled = styled_line(line, opts) |> TextLayout.truncate(inner_width)

    padded =
      String.duplicate(" ", cell.padding_x) <>
        TextLayout.pad(styled, inner_width) <> String.duplicate(" ", cell.padding_x)

    state(padded, cell.state, opts)
  end

  defp render_ansi_line(text, inner_width, cell, opts) do
    styled = text |> TextLayout.truncate(inner_width) |> TextLayout.pad(inner_width)

    padded =
      String.duplicate(" ", cell.padding_x) <> styled <> String.duplicate(" ", cell.padding_x)

    state(padded, cell.state, opts)
  end

  defp styled_line(%Line{} = line, opts), do: Enum.map_join(line.parts, &styled_part(&1, opts))
  defp styled_line(line, _opts), do: Helpers.plain_text(line)

  defp styled_part(%Text{text: text} = part, opts) do
    if Keyword.get(opts, :ansi, true), do: styled_part(part), else: text
  end

  defp styled_part(%Text{text: text, style: :title}),
    do: IO.ANSI.bright() <> text <> IO.ANSI.normal() <> IO.ANSI.black()

  defp styled_part(%Text{text: text, style: :accent}),
    do: IO.ANSI.underline() <> text <> IO.ANSI.no_underline()

  defp styled_part(%Text{text: text, style: :warning}),
    do: IO.ANSI.yellow() <> text <> IO.ANSI.black()

  defp styled_part(%Text{text: text}), do: text

  defp state(text, :success, opts), do: Theme.tool_success(text, opts)
  defp state(text, :error, opts), do: Theme.tool_error(text, opts)
  defp state(text, _state, opts), do: Theme.cell(text, opts)
end
