defmodule Tilde.Tool.Viewer.Read do
  @moduledoc "Semantic renderer for file read tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    Tilde.Tool.View.call("read",
      segments: [path_segment(block), range_segment(block)] |> Enum.reject(&is_nil/1),
      tags: read_tags(block) |> Enum.reject(&blank?/1)
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    expanded? = Keyword.get(opts, :expanded?, false)
    lines = output_lines(block)
    visible = if expanded?, do: lines, else: []

    Tilde.Tool.View.result(
      lines: visible,
      hidden_lines: if(expanded?, do: 0, else: length(lines)),
      waiting?: block.status in [:queued, :running, :streaming] and lines == []
    )
  end

  defp path_segment(block) do
    path =
      Viewer.Default.fetch_key(block.args, :file_path) ||
        Viewer.Default.fetch_key(block.args, :path)

    %{text: path || "...", color: :accent}
  end

  defp range_segment(block) do
    case line_range(block) do
      "" -> nil
      range -> %{text: range, color: :warning}
    end
  end

  defp line_range(block) do
    offset = Viewer.Default.fetch_key(block.args, :offset)
    limit = Viewer.Default.fetch_key(block.args, :limit)

    cond do
      blank?(offset) and blank?(limit) ->
        ""

      blank?(limit) ->
        ":#{offset || 1}"

      true ->
        start_line = int(offset, 1)
        end_line = start_line + int(limit, 1) - 1
        ":#{start_line}-#{end_line}"
    end
  end

  defp read_tags(block) do
    case Viewer.Default.fetch_key(block.result, :truncation) do
      truncation when is_map(truncation) ->
        if Viewer.Default.fetch_key(truncation, :truncated), do: ["truncated"], else: []

      _other ->
        []
    end
  end

  defp output_lines(block) do
    case Viewer.Default.output_lines(block) do
      [] -> Viewer.Default.result_content_lines(block.result)
      lines -> lines
    end
  end

  defp int(value, _default) when is_integer(value), do: value

  defp int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp int(_value, default), do: default

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
