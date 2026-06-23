defmodule Tilde.View.Heading do
  @moduledoc """
  Shared renderer-neutral heading lines for block-like console surfaces.

  A heading is the semantic line used for compact identities such as a tool
  invocation or an interactive choice prompt. Renderers decide whether the
  title becomes bold, bright, or another local affordance.
  """

  alias Tilde.View.{Line, Text}

  @type segment :: %{
          optional(:text) => term(),
          optional(:color) => atom(),
          optional(:style) => atom(),
          optional(:prefix) => String.t()
        }

  @doc "Builds a heading line with a title, optional detail, tags, and suffix."
  @spec line(String.t(), keyword()) :: Line.t()
  def line(title, opts \\ []) do
    detail = Keyword.get(opts, :detail)
    segments = Keyword.get(opts, :segments, [])
    tags = Keyword.get(opts, :tags, []) |> reject_blank() |> Enum.map(&to_string/1)
    suffix = Keyword.get(opts, :suffix)

    parts =
      [Text.new(title, :title)] ++
        detail_parts(detail) ++
        segment_parts(segments) ++
        tag_parts(tags) ++
        suffix_parts(suffix)

    Line.new(parts, role: :title)
  end

  defp detail_parts(nil), do: []
  defp detail_parts(""), do: []
  defp detail_parts(detail), do: [Text.new(" " <> to_string(detail), :accent)]

  defp segment_parts(segments) do
    Enum.flat_map(segments, fn segment ->
      text = segment_text(segment)

      if blank?(text) do
        []
      else
        [Text.new(segment_prefix(segment, text) <> to_string(text), segment_style(segment))]
      end
    end)
  end

  defp segment_text(%{text: text}), do: text
  defp segment_text(text), do: text

  defp segment_prefix(%{prefix: prefix}, _text) when is_binary(prefix), do: prefix

  defp segment_prefix(_segment, text),
    do: if(String.starts_with?(to_string(text), ":"), do: "", else: " ")

  defp segment_style(%{style: style}), do: normalize_style(style)
  defp segment_style(%{color: color}), do: normalize_style(color)
  defp segment_style(_segment), do: :plain

  defp tag_parts([]), do: []

  defp tag_parts(tags), do: [Text.new(" [#{Enum.join(tags, ", ")}]", :muted)]

  defp suffix_parts(nil), do: []
  defp suffix_parts(""), do: []
  defp suffix_parts(suffix), do: [Text.new(" (#{suffix})", :muted)]

  defp normalize_style(:dim), do: :muted
  defp normalize_style(:accent), do: :accent
  defp normalize_style(:muted), do: :muted
  defp normalize_style(:success), do: :success
  defp normalize_style(:error), do: :error
  defp normalize_style(:warning), do: :warning
  defp normalize_style(_style), do: :plain

  defp reject_blank(values), do: Enum.reject(values, &blank?/1)

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
