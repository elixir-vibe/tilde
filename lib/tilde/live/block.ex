defmodule Tilde.Live.Block do
  @moduledoc """
  Dispatcher component for semantic transcript blocks.
  """

  use Phoenix.Component

  import Tilde.Live.ViewRenderer

  alias Tilde.View.Builder

  attr(:block, :any, required: true)

  def block(assigns) do
    ~H"""
    <.cell cell={Builder.block(@block)} />
    """
  end
end
