defmodule Tilde.View.Helpers do
  @moduledoc """
  Pi-inspired shared semantic view helpers.
  """

  alias Tilde.View.{Line, Text}

  @spec text(term(), Text.style()) :: Text.t()
  def text(value, style \\ :plain), do: Text.new(value, style)

  @spec line([Text.t() | String.t()] | Text.t() | String.t(), keyword()) :: Line.t()
  def line(parts, opts \\ []), do: Line.new(parts, opts)

  @spec tool_call(String.t(), keyword()) :: Line.t()
  def tool_call(title, opts \\ []) do
    segments = Keyword.get(opts, :segments, [])
    tags = Keyword.get(opts, :tags, []) |> reject_blank() |> Enum.map(&to_string/1)
    suffix = Keyword.get(opts, :suffix)

    parts =
      [text(title, :title)] ++ segment_parts(segments) ++ tag_parts(tags) ++ suffix_parts(suffix)

    line(parts, role: :title)
  end

  def metadata(value), do: line(text(value, :muted), role: :metadata)
  def primary(value), do: line(text(value, :primary), role: :primary)
  def muted(value), do: line(text(value, :muted), role: :muted)
  def error(value), do: line(text(value, :error), role: :error)
  def hint(value), do: line(text(value, :muted), role: :hint)

  def expand_hint, do: hint("(ctrl+o to expand)")
  def collapse_hint, do: hint("(ctrl+o to collapse)")
  def hidden(count, unit \\ "more"), do: muted("… #{count} #{unit}")

  @spec plain_text(Line.t() | :blank | String.t()) :: String.t()
  def plain_text(%Line{} = line), do: Line.text(line)
  def plain_text(:blank), do: ""
  def plain_text(value), do: to_string(value)

  defp segment_parts(segments) do
    Enum.flat_map(segments, fn segment ->
      text = Map.get(segment, :text)

      if blank?(text) do
        []
      else
        style = Map.get(segment, :style) || Map.get(segment, :color) || :accent
        prefix = Map.get(segment, :prefix, " ")
        [Text.new(prefix <> to_string(text), style)]
      end
    end)
  end

  defp tag_parts([]), do: []

  defp tag_parts(tags),
    do: [Text.new(" [#{Enum.join(tags, ", ")} ]" |> String.replace(" ]", "]"), :muted)]

  defp suffix_parts(nil), do: []
  defp suffix_parts(""), do: []
  defp suffix_parts(suffix), do: [Text.new(" (#{suffix})", :muted)]

  defp reject_blank(values), do: Enum.reject(values, &blank?/1)

  defp blank?(nil), do: true
  defp blank?(false), do: true
  defp blank?(""), do: true
  defp blank?(_value), do: false
end
