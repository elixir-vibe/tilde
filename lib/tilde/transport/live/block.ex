defmodule Tilde.Transport.Live.Block do
  @moduledoc """
  Dispatcher component for semantic transcript blocks.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.ViewRenderer

  attr(:block, :any, required: true)

  def block(assigns) do
    ~H"""
    <.cell cell={Tilde.Viewable.to_view(@block)} />
    """
  end
end
