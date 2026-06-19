defmodule Tilde.Tool.Viewer.WebSearch do
  @moduledoc "Semantic renderer for web search tool calls."

  @behaviour Tilde.Tool.Viewer

  alias Tilde.Core.Block
  alias Tilde.Tool.Viewer

  @impl true
  def call(%Block{} = block) do
    query = Viewer.Default.fetch_key(block.args, :query)
    type = Viewer.Default.fetch_key(block.args, :type)
    category = Viewer.Default.fetch_key(block.args, :category)
    num_results = Viewer.Default.fetch_key(block.args, :numResults)

    Tilde.Tool.View.call("web",
      segments: if(blank?(query), do: [], else: [%{text: query, color: :accent}]),
      tags: [tag_unless_default(type, "auto"), category] |> Enum.reject(&blank?/1),
      suffix: if(blank?(num_results), do: nil, else: "#{num_results} results")
    )
  end

  @impl true
  def result(%Block{} = block, opts \\ []) do
    case results(block.result) do
      [] ->
        Viewer.Default.result(block, opts)

      results ->
        expanded? = Keyword.get(opts, :expanded?, false)
        limit = if expanded?, do: length(results), else: 1
        visible = Enum.take(results, limit)

        Tilde.Tool.View.result(
          entries: Enum.map(visible, &result_entry(&1, expanded?)),
          hidden_lines: if(expanded?, do: 0, else: max(length(results) - length(visible), 0)),
          hidden_unit: "more results"
        )
    end
  end

  defp result_entry(result, expanded?) do
    title = field(result, :title) || "Untitled"
    url = field(result, :url)
    author = field(result, :author)
    date = field(result, :publishedDate) |> published_date()

    metadata = [url, author, date] |> Enum.reject(&blank?/1) |> Enum.join(" · ")

    body =
      if expanded? do
        [field(result, :summary), first_highlight(result), field(result, :text)]
      else
        [field(result, :summary), first_highlight(result)]
      end
      |> Enum.reject(&blank?/1)
      |> Enum.take(1)

    %{title: title, metadata: metadata, body: body}
  end

  defp results(result) do
    case field(result, :results) do
      results when is_list(results) -> results
      _other -> []
    end
  end

  defp first_highlight(result) do
    case field(result, :highlights) do
      [highlight | _] -> highlight
      _other -> nil
    end
  end

  defp published_date(nil), do: nil
  defp published_date(<<date::binary-size(10), _rest::binary>>), do: date
  defp published_date(date), do: to_string(date)

  defp tag_unless_default(value, default),
    do: if(to_string(value || "") == default, do: nil, else: value)

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_value, _key), do: nil

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
