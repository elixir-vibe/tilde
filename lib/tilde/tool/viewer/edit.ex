defmodule Tilde.Tool.Viewer.Edit do
  @moduledoc "Semantic renderer for exact-replacement edit tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    path =
      Viewer.Default.fetch_key(block.args, :file_path) ||
        Viewer.Default.fetch_key(block.args, :path)

    Tilde.Tool.View.call("edit", segments: [%{text: path || "...", color: :accent}])
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    case diff_lines(block.result) do
      [] ->
        Viewer.Default.result(block, opts)

      lines ->
        expanded? = Keyword.get(opts, :expanded?, false)
        limit = Keyword.get(opts, :line_limit, 8)
        visible = if expanded?, do: lines, else: Enum.take(lines, limit)

        Tilde.Tool.View.result(
          lines: visible,
          hidden_lines: if(expanded?, do: 0, else: max(length(lines) - length(visible), 0))
        )
    end
  end

  defp diff_lines(result) do
    result
    |> diff_text()
    |> split_lines()
  end

  defp diff_text(result) when is_map(result) do
    Viewer.Default.fetch_key(result, :diff) ||
      result |> Viewer.Default.fetch_key(:details) |> details_diff()
  end

  defp diff_text(_result), do: nil

  defp details_diff(details) when is_map(details), do: Viewer.Default.fetch_key(details, :diff)
  defp details_diff(_details), do: nil

  defp split_lines(nil), do: []
  defp split_lines(""), do: []

  defp split_lines(text) do
    text
    |> String.split("\n")
    |> then(fn lines -> if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines end)
  end
end
