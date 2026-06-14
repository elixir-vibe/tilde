defmodule Tilde.TUI.ViewRenderer do
  @moduledoc """
  Width-aware ANSI renderer for shared `Tilde.View.Cell` values.
  """

  alias Tilde.TUI.{Markdown, Theme}
  alias Tilde.View.Cell

  @doc "Renders a cell to terminal text."
  @spec render(Cell.t(), pos_integer(), keyword()) :: String.t()
  def render(cell, width, opts \\ [])

  def render(%Cell{kind: :message} = cell, width, opts) do
    body =
      cell
      |> message_lines()
      |> Enum.map_join("\n", &truncate(&1, width))

    [Theme.muted(to_string(cell.role), opts), body]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  def render(%Cell{} = cell, width, opts) do
    inner_width = max(width - cell.padding_x * 2, 1)
    blank = ""

    lines =
      List.duplicate(blank, cell.padding_y) ++
        cell.lines ++
        List.duplicate(blank, cell.padding_y)

    lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, index} ->
      render_cell_line(line, inner_width, cell, opts, index)
    end)
  end

  defp message_lines(%Cell{runs: [_ | _] = runs}),
    do: text_lines(Enum.map_join(runs, & &1.text), 0)

  defp message_lines(%Cell{format: :markdown, source: source}), do: Markdown.render_lines(source)

  defp message_lines(%Cell{source: source}), do: text_lines(source, 0)

  defp text_lines(text, indent) do
    prefix = String.duplicate(" ", indent)

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map(&(prefix <> &1))
  end

  defp render_cell_line(line, inner_width, cell, opts, index) do
    text = line |> to_string() |> truncate(inner_width)
    styled = style_line(text, cell, index, opts)

    padded =
      String.duplicate(" ", cell.padding_x) <>
        pad(styled, inner_width) <> String.duplicate(" ", cell.padding_x)

    state(padded, cell.state, opts)
  end

  defp style_line(text, %Cell{kind: :tool, padding_y: padding_y}, padding_y, opts) do
    if Keyword.get(opts, :ansi, true), do: style_tool_call(text), else: text
  end

  defp style_line(text, _cell, _index, _opts), do: text

  defp style_tool_call(""), do: ""

  defp style_tool_call(text) do
    case String.split(text, " ", parts: 2) do
      [name, rest] ->
        IO.ANSI.bright() <>
          name <>
          IO.ANSI.normal() <>
          IO.ANSI.black() <> " " <> IO.ANSI.underline() <> rest <> IO.ANSI.no_underline()

      [name] ->
        IO.ANSI.bright() <> name <> IO.ANSI.normal() <> IO.ANSI.black()
    end
  end

  defp state(text, :pending, opts), do: Theme.tool_pending(text, opts)
  defp state(text, :success, opts), do: Theme.tool_success(text, opts)
  defp state(text, :error, opts), do: Theme.tool_error(text, opts)
  defp state(text, _state, opts), do: Theme.cell(text, opts)

  defp pad(text, width) do
    text <> String.duplicate(" ", max(width - visible_width(text), 0))
  end

  defp truncate(text, width) do
    if visible_width(text) <= width do
      text
    else
      text
      |> String.graphemes()
      |> Enum.take(max(width - 1, 0))
      |> Enum.join()
      |> Kernel.<>("…")
    end
  end

  defp visible_width(text), do: text |> strip_ansi() |> String.length()

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
  end
end
