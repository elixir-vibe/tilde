defmodule Tilde.Tool.Viewer.Default do
  @moduledoc """
  Default semantic renderer for generic tool blocks.
  """

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.{Block, Stream}
  alias Tilde.Tool.View.Stream, as: StreamView

  @impl true
  def call(%Block{} = block) do
    Tilde.Tool.View.call(block.name || "tool",
      segments: call_segments(block.args),
      tags: call_tags(block),
      suffix: call_suffix(block)
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    line_limit = Keyword.get(opts, :line_limit, 8)
    expanded? = Keyword.get(opts, :expanded?, false)

    lines = output_lines(block)
    visible_lines = visible_lines(lines, expanded?, line_limit)
    streams = StreamView.views(block.streams, if(expanded?, do: :all, else: line_limit), :tail)

    Tilde.Tool.View.result(
      metadata_rows: metadata_rows(block),
      lines: visible_lines,
      streams: streams,
      hidden_lines: hidden_lines(lines, visible_lines, streams, expanded?),
      waiting?: waiting?(block, visible_lines, streams)
    )
  end

  @doc "Returns all output lines across streams, annotated by stream kind when useful."
  @spec output_lines(Block.t()) :: [String.t()]
  def output_lines(%Block{kind: :tool, streams: streams}) do
    Enum.flat_map(streams, &stream_lines/1)
  end

  @doc "Returns text lines from a first-party Tilde tool result content payload."
  @spec result_content_lines(term()) :: [String.t()]
  def result_content_lines(result) do
    result
    |> result_text()
    |> split_lines()
  end

  defp visible_lines(lines, true, _limit), do: lines
  defp visible_lines(lines, false, limit), do: take_tail(lines, limit)

  defp hidden_lines(_lines, _visible_lines, _streams, true), do: 0

  defp hidden_lines(lines, visible_lines, [], false) do
    max(length(lines) - length(visible_lines), 0)
  end

  defp hidden_lines(_lines, _visible_lines, streams, false) do
    Enum.reduce(streams, 0, &(&1.hidden_lines + &2))
  end

  defp take_tail(_lines, limit) when limit <= 0, do: []
  defp take_tail(lines, limit), do: Enum.take(lines, -limit)

  defp stream_lines(%Stream{kind: :stdout} = stream), do: Stream.lines(stream)

  defp stream_lines(%Stream{kind: kind} = stream) do
    Enum.map(Stream.lines(stream), &"#{kind}: #{&1}")
  end

  defp result_text(%{content: content}) when is_list(content), do: content_text(content)
  defp result_text(%{"content" => content}) when is_list(content), do: content_text(content)
  defp result_text(%{text: text}) when is_binary(text), do: text
  defp result_text(%{"text" => text}) when is_binary(text), do: text
  defp result_text(text) when is_binary(text), do: text
  defp result_text(_result), do: ""

  defp content_text(content) do
    content
    |> Enum.filter(&(fetch_key(&1, :type) == "text"))
    |> Enum.map_join("\n", &(fetch_key(&1, :text) || ""))
  end

  defp split_lines(""), do: []

  defp split_lines(text) do
    text
    |> String.split("\n")
    |> then(fn lines -> if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines end)
  end

  defp metadata_rows(block) do
    [
      metadata_row(:cwd, fetch_key(block.args, :cwd)),
      metadata_row(:exit, fetch_key(block.result, :exit_code)),
      metadata_row(:duration, block.metadata |> fetch_key(:duration_ms) |> duration())
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp metadata_row(_key, nil), do: nil
  defp metadata_row(key, value), do: {key, to_string(value)}

  def fetch_key(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  def fetch_key(_value, _key), do: nil

  defp duration(nil), do: nil
  defp duration(milliseconds) when is_integer(milliseconds), do: "#{milliseconds}ms"
  defp duration(value), do: value

  defp call_segments(args) when map_size(args) == 0, do: []

  defp call_segments(%{command: command}) when is_binary(command),
    do: [%{text: command, color: :accent}]

  defp call_segments(%{"command" => command}) when is_binary(command),
    do: [%{text: command, color: :accent}]

  defp call_segments(%{url: url}) when is_binary(url), do: [%{text: url, color: :accent}]
  defp call_segments(%{"url" => url}) when is_binary(url), do: [%{text: url, color: :accent}]

  defp call_segments(args) do
    args
    |> Enum.take(3)
    |> Enum.map(fn {key, value} -> %{text: "#{key}=#{inspect(value)}", color: :accent} end)
  end

  defp call_tags(block) do
    case fetch_key(block.metadata, :tags) do
      tags when is_list(tags) -> tags |> Enum.reject(&blank?/1) |> Enum.map(&to_string/1)
      tag when is_binary(tag) -> [tag]
      _other -> []
    end
  end

  defp call_suffix(block) do
    case fetch_key(block.metadata, :suffix) do
      suffix when is_binary(suffix) and suffix != "" ->
        suffix

      suffix when is_integer(suffix) or is_float(suffix) or is_boolean(suffix) ->
        to_string(suffix)

      _other ->
        nil
    end
  end

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false

  defp waiting?(block, visible_lines, streams) do
    pending?(block.status) and visible_lines == [] and Enum.all?(streams, &(&1.lines == []))
  end

  defp pending?(status), do: status in [:queued, :running, :streaming]
end
