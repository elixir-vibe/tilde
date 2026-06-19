defmodule Tilde.Tool.Viewer.Fetch do
  @moduledoc "Semantic renderer for URL fetch tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.View.Stream, as: StreamView
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    url = Viewer.Default.fetch_key(block.args, :url)
    format = Viewer.Default.fetch_key(block.args, :format)
    selector = Viewer.Default.fetch_key(block.args, :selector)

    Tilde.Tool.View.call("fetch",
      segments: if(blank?(url), do: [], else: [%{text: url, color: :accent}]),
      tags: [tag_unless_default(format, "markdown"), selector] |> Enum.reject(&blank?/1)
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    line_limit = Keyword.get(opts, :line_limit, 8)
    expanded? = Keyword.get(opts, :expanded?, false)

    lines = Viewer.Default.output_lines(block)
    visible_lines = if expanded?, do: lines, else: Enum.take(lines, line_limit)

    Tilde.Tool.View.result(
      lines: visible_lines,
      streams: StreamView.views(block.streams, if(expanded?, do: :all, else: line_limit), :head),
      hidden_lines: if(expanded?, do: 0, else: max(length(lines) - length(visible_lines), 0)),
      waiting?: waiting?(block, visible_lines)
    )
  end

  defp waiting?(block, visible_lines) do
    block.status in [:queued, :running, :streaming] and visible_lines == []
  end

  defp tag_unless_default(value, default),
    do: if(to_string(value || "") == default, do: nil, else: value)

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
