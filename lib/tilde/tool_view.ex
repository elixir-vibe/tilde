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

    base_view(block, visible, max(length(lines) - length(visible), 0), false)
  end

  @doc "Builds an expanded tool view with all output."
  @spec expanded(Block.t()) :: t()
  def expanded(%Block{kind: :tool} = block) do
    base_view(block, output_lines(block), 0, true)
  end

  @doc "Returns all output lines across streams, annotated by stream kind when useful."
  @spec output_lines(Block.t()) :: [String.t()]
  def output_lines(%Block{kind: :tool, streams: streams}) do
    Enum.flat_map(streams, &stream_lines/1)
  end

  defp base_view(block, visible_lines, hidden_lines, expanded?) do
    %{
      id: block.id,
      name: block.name || "tool",
      status: block.status || :running,
      args: block.args,
      arg_summary: arg_summary(block.args),
      lines: visible_lines,
      hidden_lines: hidden_lines,
      expanded?: expanded?,
      actions: block.actions,
      result: block.result,
      metadata: block.metadata
    }
  end

  defp line_limit(%Block{display: %{compact_limit: {:lines, limit}}}), do: limit
  defp line_limit(_block), do: 8

  defp stream_lines(%Stream{kind: :stdout} = stream), do: Stream.lines(stream)

  defp stream_lines(%Stream{kind: kind} = stream) do
    Enum.map(Stream.lines(stream), &"#{kind}: #{&1}")
  end

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
