defmodule Tilde.Live.Message do
  @moduledoc """
  Compatibility component for semantic message blocks.

  New rendering goes through the shared `Tilde.View` cell pipeline so LiveView,
  TUI, and SSH stay aligned.
  """

  use Phoenix.Component

  import Tilde.Live.ViewRenderer

  alias Tilde.View.Builder

  attr(:block, :any, required: true)

  def message(assigns) do
    ~H"""
    <.cell cell={Builder.block(@block)} />
    """
  end
end
