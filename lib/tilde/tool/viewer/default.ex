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
    visible_lines = if expanded?, do: lines, else: Enum.take(lines, line_limit)
    streams = stream_views(block.streams, if(expanded?, do: :all, else: line_limit))

    Tilde.Tool.View.result(
      metadata_rows: metadata_rows(block),
      lines: visible_lines,
      streams: streams,
      hidden_lines: if(expanded?, do: 0, else: max(length(lines) - length(visible_lines), 0)),
      waiting?: waiting?(block, visible_lines, streams)
    )
  end

  @doc "Returns all output lines across streams, annotated by stream kind when useful."
  @spec output_lines(Block.t()) :: [String.t()]
  def output_lines(%Block{kind: :tool, streams: streams}) do
    Enum.flat_map(streams, &stream_lines/1)
  end

  defp stream_views(streams, :all) do
    Enum.map(streams, fn stream ->
      lines = Stream.lines(stream)

      %StreamView{
        id: stream.id,
        kind: stream.kind,
        lines: lines,
        hidden_lines: 0,
        byte_count: Stream.byte_count(stream),
        line_count: length(lines)
      }
    end)
  end

  defp stream_views(streams, limit) do
    {views, _remaining} =
      Enum.map_reduce(streams, limit, fn stream, remaining ->
        lines = Stream.lines(stream)
        visible = Enum.take(lines, max(remaining, 0))

        view = %StreamView{
          id: stream.id,
          kind: stream.kind,
          lines: visible,
          hidden_lines: max(length(lines) - length(visible), 0),
          byte_count: Stream.byte_count(stream),
          line_count: length(lines)
        }

        {view, max(remaining - length(visible), 0)}
      end)

    views
  end

  defp stream_lines(%Stream{kind: :stdout} = stream), do: Stream.lines(stream)

  defp stream_lines(%Stream{kind: kind} = stream) do
    Enum.map(Stream.lines(stream), &"#{kind}: #{&1}")
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
