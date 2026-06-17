defmodule Tilde.Renderer.TUI.Markdown do
  @moduledoc """
  Terminal-oriented Markdown rendering helpers.

  This is renderer-local: Markdown remains source text in the semantic session.
  Web renderers can emit semantic HTML tables, while TUI renderers derive
  ASCII-grid table views from MDEx AST source positions.
  """

  alias Tilde.Renderer.TUI.Theme

  @doc "Renders Markdown into terminal lines, replacing MDEx tables and thematic breaks with terminal views."
  @spec render_lines(String.t(), pos_integer(), keyword()) :: [String.t()]
  def render_lines(markdown, width \\ 80, opts \\ []) when is_binary(markdown) do
    with true <- Code.ensure_loaded?(MDEx),
         {:ok, document} <- MDEx.parse_document(markdown, extension: [table: true]) do
      render_with_special_blocks(markdown, document, width, opts)
    else
      _other -> String.split(String.trim_trailing(markdown), "\n")
    end
  end

  defp render_with_special_blocks(markdown, document, width, opts) do
    lines = String.split(String.trim_trailing(markdown), "\n")

    blocks =
      document.nodes |> Enum.filter(&special_block?/1) |> Enum.sort_by(&source_start_line/1)

    if blocks == [] do
      lines
    else
      {chunks, next_line} =
        Enum.map_reduce(blocks, 1, fn block, next_line ->
          {start_line, end_line} = source_range(block)

          chunk = [
            line_slice(lines, next_line, start_line - 1),
            render_special_block(block, width, opts)
          ]

          {chunk, end_line + 1}
        end)

      [chunks, line_slice(lines, next_line, length(lines))]
      |> List.flatten()
    end
  end

  defp special_block?(%{__struct__: module}),
    do: module in [Module.concat(MDEx, Table), Module.concat(MDEx, ThematicBreak)]

  defp special_block?(_node), do: false

  defp source_start_line(block), do: block.sourcepos.start |> elem(0)
  defp source_range(table), do: {table.sourcepos.start |> elem(0), table.sourcepos.end |> elem(0)}

  defp line_slice(_lines, start_line, end_line) when start_line > end_line, do: []

  defp line_slice(lines, start_line, end_line) do
    lines
    |> Enum.slice((start_line - 1)..(end_line - 1)//1)
    |> Enum.reject(&(&1 == ""))
  end

  defp render_special_block(%{__struct__: module} = block, width, opts) do
    cond do
      module == Module.concat(MDEx, Table) ->
        render_table(block)

      module == Module.concat(MDEx, ThematicBreak) ->
        line = String.duplicate("─", max(width, 3))

        line
        |> Theme.muted(opts)
        |> List.duplicate(3)
    end
  end

  defp render_table(table) do
    rows = Enum.map(table.nodes, &table_row/1)
    widths = column_widths(rows)
    alignments = (table.alignments || []) |> List.to_tuple()
    top = border_line(widths, "┌", "┬", "┐")
    middle = border_line(widths, "├", "┼", "┤")
    bottom = border_line(widths, "└", "┴", "┘")

    rows
    |> Enum.with_index()
    |> Enum.flat_map(fn {row, index} ->
      line = row_line(row, widths, alignments)
      if index == 0, do: [top, line, middle], else: [line]
    end)
    |> Kernel.++([bottom])
  end

  defp table_row(row), do: Enum.map(row.nodes, &cell_text/1)

  defp cell_text(cell) do
    cell.nodes
    |> Enum.map_join(&node_text/1)
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp node_text(%{literal: literal}) when is_binary(literal), do: literal
  defp node_text(%{nodes: nodes}) when is_list(nodes), do: Enum.map_join(nodes, &node_text/1)
  defp node_text(_node), do: ""

  defp column_widths(rows) do
    rows
    |> Enum.zip_with(fn column ->
      column
      |> Enum.map(&String.length/1)
      |> Enum.max(fn -> 0 end)
    end)
  end

  defp border_line(widths, left, join, right) do
    widths
    |> Enum.map_join(join, &String.duplicate("─", &1 + 2))
    |> then(&(left <> &1 <> right))
  end

  defp row_line(row, widths, alignments) do
    row
    |> Enum.zip(widths)
    |> Enum.with_index()
    |> Enum.map_join("│", fn {{cell, width}, index} ->
      alignment = alignment_at(alignments, index)
      " " <> align(cell, width, alignment) <> " "
    end)
    |> then(&("│" <> &1 <> "│"))
  end

  defp alignment_at(alignments, index) do
    if index < tuple_size(alignments), do: elem(alignments, index), else: :none
  end

  defp align(text, width, :right), do: String.pad_leading(text, width)
  defp align(text, width, :center), do: center(text, width)
  defp align(text, width, _alignment), do: String.pad_trailing(text, width)

  defp center(text, width) do
    padding = max(width - String.length(text), 0)
    left = div(padding, 2)
    right = padding - left
    String.duplicate(" ", left) <> text <> String.duplicate(" ", right)
  end
end
