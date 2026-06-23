defmodule Tilde.Transport.Live.Line do
  @moduledoc """
  LiveView components for shared `Tilde.View.Line` and `Tilde.View.Text` values.
  """

  use Phoenix.Component

  alias Tilde.View.{Line, Text}

  attr(:line, :any, required: true)

  def line(%{line: %Line{} = line} = assigns) do
    assigns = assign(assigns, :parts, line.parts)

    ~H"""
    <.part :for={part <- @parts} part={part} />
    """
  end

  def line(%{line: :blank} = assigns) do
    ~H"""
    <br />
    """
  end

  def line(assigns) do
    ~H"""
    {@line}
    """
  end

  attr(:part, Text, required: true)

  def part(assigns) do
    ~H"""
    <span class={["text", @part.style]}>{@part.text}</span>
    """
  end
end
