defmodule Tilde.ToolView do
  @moduledoc """
  Derived compact and expanded views for tool blocks.

  This module returns semantic view data, not strings with terminal escapes or
  HTML. Renderers decide how to draw the view.
  """

  alias Tilde.{Block, Stream}

  @type t :: map()

  @doc "Builds a compact or expanded view depending on the block display state."
  @spec view(Block.t()) :: t()
  def view(%Block{kind: :tool, display: %{expanded?: true}} = block), do: expanded(block)
  def view(%Block{kind: :tool} = block), do: compact(block)

  @doc "Builds a compact tool view with output truncation."
  @spec compact(Block.t()) :: t()
  def compact(%Block{kind: :tool} = block) do
    limit = line_limit(block)
    lines = output_lines(block)
    visible = Enum.take(lines, limit)
    streams = stream_views(block.streams, limit)

    base_view(block, visible, streams, max(length(lines) - length(visible), 0), false)
  end

  @doc "Builds an expanded tool view with all output."
  @spec expanded(Block.t()) :: t()
  def expanded(%Block{kind: :tool} = block) do
    base_view(block, output_lines(block), stream_views(block.streams, :all), 0, true)
  end

  @doc "Returns all output lines across streams, annotated by stream kind when useful."
  @spec output_lines(Block.t()) :: [String.t()]
  def output_lines(%Block{kind: :tool, streams: streams}) do
    Enum.flat_map(streams, &stream_lines/1)
  end

  defp base_view(block, visible_lines, streams, hidden_lines, expanded?) do
    %{
      id: block.id,
      name: block.name || "tool",
      status: block.status || :running,
      args: block.args,
      call_segments: call_segments(block.args),
      call_tags: call_tags(block),
      call_suffix: call_suffix(block),
      arg_summary: arg_summary(block.args),
      metadata_rows: metadata_rows(block),
      waiting?: waiting?(block, visible_lines, streams),
      lines: visible_lines,
      streams: streams,
      hidden_lines: hidden_lines,
      expanded?: expanded?,
      actions: block.actions,
      result: block.result,
      metadata: block.metadata
    }
  end

  defp waiting?(block, visible_lines, streams) do
    pending?(block.status) and visible_lines == [] and Enum.all?(streams, &(&1.lines == []))
  end

  defp pending?(status), do: status in [:queued, :running, :streaming]

  defp line_limit(%Block{display: %{compact_limit: {:lines, limit}}}), do: limit
  defp line_limit(_block), do: 8

  defp stream_views(streams, :all) do
    Enum.map(streams, fn stream ->
      lines = Stream.lines(stream)

      %{
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

        view = %{
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

  defp fetch_key(map, key) when is_map(map) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp fetch_key(_value, _key), do: nil

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

  defp arg_summary(args) when map_size(args) == 0, do: ""

  defp arg_summary(%{command: command}) when is_binary(command), do: command
  defp arg_summary(%{"command" => command}) when is_binary(command), do: command
  defp arg_summary(%{url: url}) when is_binary(url), do: url
  defp arg_summary(%{"url" => url}) when is_binary(url), do: url

  defp arg_summary(args) do
    args
    |> Enum.take(3)
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{inspect(value)}" end)
  end
end
