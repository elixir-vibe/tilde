defmodule Tilde.View.Helpers do
  @moduledoc """
  Pi-inspired shared semantic view helpers.
  """

  alias Tilde.View.{Heading, Line, Text}

  @spec text(term(), Text.style()) :: Text.t()
  def text(value, style \\ :plain), do: Text.new(value, style)

  @spec line([Text.t() | String.t()] | Text.t() | String.t(), keyword()) :: Line.t()
  def line(parts, opts \\ []), do: Line.new(parts, opts)

  @spec tool_call(String.t(), keyword()) :: Line.t()
  def tool_call(title, opts \\ []), do: Heading.line(title, opts)

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
end
