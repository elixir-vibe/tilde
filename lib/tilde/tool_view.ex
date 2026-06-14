defmodule Tilde.ToolView do
  @moduledoc """
  Derived compact and expanded views for tool blocks.

  This module returns semantic view data, not strings with terminal escapes or
  HTML. Renderers decide how to draw the view.
  """

  alias Tilde.{Block, ToolRenderer}

  @type t :: map()

  @doc "Builds a compact or expanded view depending on the block display state."
  @spec view(Block.t()) :: t()
  def view(%Block{kind: :tool, display: %{expanded?: true}} = block), do: expanded(block)
  def view(%Block{kind: :tool} = block), do: compact(block)

  @doc "Builds a compact tool view with output truncation."
  @spec compact(Block.t()) :: t()
  def compact(%Block{kind: :tool} = block) do
    build(block, expanded?: false, line_limit: line_limit(block))
  end

  @doc "Builds an expanded tool view with all output."
  @spec expanded(Block.t()) :: t()
  def expanded(%Block{kind: :tool} = block) do
    build(block, expanded?: true, line_limit: :all)
  end

  @doc "Returns all output lines across streams, annotated by stream kind when useful."
  @spec output_lines(Block.t()) :: [String.t()]
  def output_lines(%Block{} = block), do: ToolRenderer.Default.output_lines(block)

  defp build(block, opts) do
    renderer = ToolRenderer.for(block)
    call = renderer.call(block)
    result = renderer.result(block, opts)

    %{
      id: block.id,
      name: call.title,
      status: block.status || :running,
      args: block.args,
      call_segments: call.segments,
      call_tags: call.tags,
      call_suffix: call.suffix,
      arg_summary: arg_summary(call.segments),
      metadata_rows: result.metadata_rows,
      waiting?: result.waiting?,
      lines: result.lines,
      streams: result.streams,
      hidden_lines: result.hidden_lines,
      expanded?: Keyword.get(opts, :expanded?, false),
      actions: block.actions,
      result: block.result,
      metadata: block.metadata
    }
  end

  defp line_limit(%Block{display: %{compact_limit: {:lines, limit}}}), do: limit
  defp line_limit(_block), do: 8

  defp arg_summary([]), do: ""
  defp arg_summary([%{text: text} | _segments]), do: to_string(text)
end
