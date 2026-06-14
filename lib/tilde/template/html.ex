defmodule Tilde.Template.HTML do
  @moduledoc false

  alias Tilde.View.{Cell, Helpers, Line, Text}

  @block_tags ~w(article section header footer main div p ul ol li pre blockquote table thead tbody tr td th h1 h2 h3 h4 h5 h6)
  @void_break_tags ~w(br hr)

  @spec to_cells(String.t(), keyword()) :: [Cell.t()]
  def to_cells(html, opts \\ []) do
    lines = html |> strip_unsafe() |> lines_from_html()

    [
      Cell.new(
        kind: Keyword.get(opts, :kind, :template),
        role: Keyword.get(opts, :role),
        state: Keyword.get(opts, :state, :normal),
        lines: lines,
        padding_x: Keyword.get(opts, :padding_x, 0),
        padding_y: Keyword.get(opts, :padding_y, 0),
        attrs: %{html: html}
      )
    ]
  end

  defp strip_unsafe(html) do
    html
    |> replace(~r/<!--.*?-->/s, "")
    |> replace(~r/<script\b[^>]*>.*?<\/script>/is, "")
    |> replace(~r/<style\b[^>]*>.*?<\/style>/is, "")
  end

  defp lines_from_html(html) do
    html
    |> split(~r/(<[^>]+>)/, include_captures: true, trim: false)
    |> Enum.reduce(%{lines: [], parts: [], styles: []}, &consume_token/2)
    |> flush_line()
    |> Map.fetch!(:lines)
    |> Enum.reverse()
    |> Enum.reject(&(Helpers.plain_text(&1) == ""))
  end

  defp consume_token("", state), do: state

  defp consume_token("<" <> _ = token, state) do
    consume_tag(token, state)
  end

  defp consume_token(text, state) do
    text
    |> decode_entities()
    |> String.split("\n", trim: false)
    |> Enum.reduce({state, 0}, fn chunk, {acc, index} ->
      acc = if index > 0, do: flush_line(acc), else: acc
      {append_text(acc, chunk), index + 1}
    end)
    |> elem(0)
  end

  defp consume_tag(tag, state) do
    cond do
      closing_tag?(tag) ->
        name = tag_name(tag)
        state = if name in @block_tags, do: flush_line(state), else: state
        pop_style(state, style_for_tag(tag))

      tag_name(tag) in @void_break_tags ->
        flush_line(state)

      tag_name(tag) == "li" ->
        state |> flush_line() |> append_text("• ")

      tag_name(tag) in @block_tags ->
        state |> flush_line() |> push_style(style_for_tag(tag))

      true ->
        push_style(state, style_for_tag(tag))
    end
  end

  defp append_text(state, text) do
    text = normalize_text(text)

    if text == "" do
      state
    else
      style = current_style(state.styles)
      %{state | parts: state.parts ++ [Text.new(text, style)]}
    end
  end

  defp flush_line(%{parts: []} = state), do: state

  defp flush_line(%{parts: parts} = state) do
    text = parts |> Enum.map_join(& &1.text) |> String.trim()

    if text == "" do
      %{state | parts: []}
    else
      parts = trim_parts(parts)
      %{state | lines: [Line.new(parts, role: role_for_parts(parts)) | state.lines], parts: []}
    end
  end

  defp push_style(state, nil), do: state
  defp push_style(state, style), do: %{state | styles: [style | state.styles]}

  defp pop_style(state, nil), do: state

  defp pop_style(%{styles: styles} = state, style),
    do: %{state | styles: List.delete(styles, style)}

  defp current_style([style | _]), do: style
  defp current_style([]), do: :plain

  defp role_for_parts(parts) do
    styles = Enum.map(parts, & &1.style)

    cond do
      :error in styles -> :error
      :title in styles -> :title
      :muted in styles -> :muted
      :primary in styles -> :primary
      true -> :normal
    end
  end

  defp style_for_tag(tag) do
    name = tag_name(tag)

    cond do
      name in ~w(h1 h2 h3 h4 h5 h6 strong b) -> :title
      name in ~w(em i code a) -> :accent
      class_has?(tag, ~w(error danger)) -> :error
      class_has?(tag, ~w(success ok)) -> :success
      class_has?(tag, ~w(primary)) -> :primary
      class_has?(tag, ~w(muted secondary meta)) -> :muted
      true -> nil
    end
  end

  defp class_has?(tag, names) do
    case Regex.run(~r/class\s*=\s*(["'])(.*?)\1/is, tag) do
      [_, _, classes] -> Enum.any?(names, &String.contains?(classes, &1))
      _ -> false
    end
  end

  defp tag_name(tag) do
    case Regex.run(~r/^<\/?\s*([:.A-Za-z0-9_-]+)/, tag) do
      [_, name] -> String.downcase(name)
      _ -> ""
    end
  end

  defp closing_tag?(tag), do: String.starts_with?(tag, "</")

  defp normalize_text(text) do
    text
    |> replace(~r/[ \t\r\f]+/, " ")
  end

  defp trim_parts(parts) do
    parts
    |> trim_first_part()
    |> trim_last_part()
  end

  defp trim_first_part([%Text{} = part | rest]),
    do: [%Text{part | text: String.trim_leading(part.text)} | rest]

  defp trim_first_part(parts), do: parts

  defp trim_last_part(parts) do
    case Enum.reverse(parts) do
      [%Text{} = part | rest] ->
        Enum.reverse([%Text{part | text: String.trim_trailing(part.text)} | rest])

      parts ->
        Enum.reverse(parts)
    end
  end

  defp replace(text, regex, replacement), do: Regex.replace(regex, text, replacement)
  defp split(text, regex, opts), do: Regex.split(regex, text, opts)

  defp decode_entities(text) do
    text
    |> String.replace("&nbsp;", " ")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end
end
