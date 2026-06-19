defmodule Tilde.Tool.Viewer.Read do
  @moduledoc "Semantic renderer for file read tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    Tilde.Tool.View.call("read",
      segments: [path_segment(block)],
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

    %{text: "#{path || "..."}#{line_range(block)}", color: :accent}
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
      [] -> block.result |> result_text() |> split_lines()
      lines -> lines
    end
  end

  defp result_text(%{content: content}) when is_list(content), do: content_text(content)
  defp result_text(%{"content" => content}) when is_list(content), do: content_text(content)
  defp result_text(%{text: text}) when is_binary(text), do: text
  defp result_text(%{"text" => text}) when is_binary(text), do: text
  defp result_text(text) when is_binary(text), do: text
  defp result_text(_result), do: ""

  defp content_text(content) do
    content
    |> Enum.filter(&(field(&1, :type) == "text"))
    |> Enum.map_join("\n", &(field(&1, :text) || ""))
  end

  defp split_lines(""), do: []

  defp split_lines(text) do
    text
    |> String.split("\n")
    |> then(fn lines -> if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines end)
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_value, _key), do: nil

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
