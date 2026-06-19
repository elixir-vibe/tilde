defmodule Tilde.Renderer.TUI.ViewRenderer do
  @moduledoc """
  Width-aware ANSI renderer for shared `Tilde.View.Cell` values.
  """

  alias Tilde.Renderer.TUI.{Markdown, Theme}
  alias Tilde.View.{Cell, Helpers, Line, Text}

  @doc "Renders a cell to terminal text."
  @spec render(Cell.t(), pos_integer(), keyword()) :: String.t()
  def render(cell, width, opts \\ [])

  def render(%Cell{kind: :message} = cell, width, opts) do
    body =
      cell
      |> message_lines(width, opts)
      |> Enum.map_join("\n", &truncate(&1, width))

    [Theme.muted(to_string(cell.role), opts), body]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  def render(%Cell{kind: :choice} = cell, width, opts) do
    cell
    |> render_cell_lines(width, opts)
    |> append_action_footer(cell, width, opts)
    |> Enum.join("\n")
  end

  def render(
        %Cell{kind: :tool, attrs: %{view: %{name: "read", expanded?: true, lines: [_ | _]}}} =
          cell,
        width,
        opts
      ) do
    Tilde.Renderer.TUI.ReadTool.render(cell, width, opts) |> Enum.join("\n")
  end

  def render(%Cell{} = cell, width, opts) do
    cell
    |> render_cell_lines(width, opts)
    |> Enum.join("\n")
  end

  defp render_cell_lines(%Cell{} = cell, width, opts) do
    inner_width = max(width - cell.padding_x * 2, 1)
    blank = ""

    lines =
      List.duplicate(blank, cell.padding_y) ++
        cell.lines ++
        List.duplicate(blank, cell.padding_y)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      render_cell_line(line, inner_width, cell, opts, index)
    end)
  end

  defp append_action_footer(lines, %Cell{actions: []}, _width, _opts), do: lines

  defp append_action_footer(lines, %Cell{} = cell, width, opts) do
    action_text =
      cell.actions
      |> Enum.map(&action_hint/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("    ")

    if action_text == "" do
      lines
    else
      inner_width = max(width - cell.padding_x * 2, 1)
      indent = String.duplicate(" ", max(inner_width - visible_width(action_text), 0))

      padded =
        String.duplicate(" ", cell.padding_x) <>
          indent <> Theme.muted(action_text, opts) <> String.duplicate(" ", cell.padding_x)

      lines ++ [state(padded, cell.state, opts)]
    end
  end

  defp action_hint(%{key: key, label: label}) when is_binary(key) and key != "",
    do: "#{key} #{label}"

  defp action_hint(%{label: label}), do: to_string(label)

  defp message_lines(%Cell{runs: [_ | _] = runs}, _width, _opts),
    do: text_lines(Enum.map_join(runs, & &1.text), 0)

  defp message_lines(%Cell{format: :markdown, source: source}, width, opts),
    do: Markdown.render_lines(source, width, opts)

  defp message_lines(%Cell{source: source}, _width, _opts), do: text_lines(source, 0)

  defp text_lines(text, indent) do
    prefix = String.duplicate(" ", indent)

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map(&(prefix <> &1))
  end

  defp render_cell_line(line, inner_width, cell, opts, _index) do
    text = line |> Helpers.plain_text() |> truncate(inner_width)
    styled = styled_line(line, text, opts)

    padded =
      String.duplicate(" ", cell.padding_x) <>
        pad(styled, inner_width) <> String.duplicate(" ", cell.padding_x)

    state(padded, cell.state, opts)
  end

  defp styled_line(%Line{} = line, _text, opts) do
    line.parts
    |> Enum.map_join(&styled_part(&1, opts))
    |> truncate(String.length(Helpers.plain_text(line)))
  end

  defp styled_line(_line, text, _opts), do: text

  defp styled_part(%Text{text: text} = part, opts) do
    if Keyword.get(opts, :ansi, true), do: styled_part(part), else: text
  end

  defp styled_part(%Text{text: text, style: :title}),
    do: IO.ANSI.bright() <> text <> IO.ANSI.normal() <> IO.ANSI.black()

  defp styled_part(%Text{text: text, style: :accent}),
    do: IO.ANSI.underline() <> text <> IO.ANSI.no_underline()

  defp styled_part(%Text{text: text, style: :muted}),
    do: IO.ANSI.faint() <> text <> IO.ANSI.normal() <> IO.ANSI.black()

  defp styled_part(%Text{text: text, style: :error}),
    do: IO.ANSI.red() <> text <> IO.ANSI.black()

  defp styled_part(%Text{text: text, style: :success}),
    do: IO.ANSI.green() <> text <> IO.ANSI.black()

  defp styled_part(%Text{text: text}), do: text

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
