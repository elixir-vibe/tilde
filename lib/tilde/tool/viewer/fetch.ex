defmodule Tilde.Tool.Viewer.Fetch do
  @moduledoc "Semantic renderer for URL fetch tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
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
  def result(%Block{} = block, opts \\ []), do: Viewer.Default.result(block, opts)

  defp tag_unless_default(value, default),
    do: if(to_string(value || "") == default, do: nil, else: value)

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
