defmodule Tilde.Live.Tool do
  @moduledoc """
  Compatibility component for semantic tool blocks.

  New rendering goes through the shared `Tilde.View` cell pipeline so LiveView,
  TUI, and SSH stay aligned.
  """

  use Phoenix.Component

  import Tilde.Live.ViewRenderer

  alias Tilde.View.Builder

  attr(:block, :any, required: true)
  attr(:toggle_event, :string, default: "tilde:toggle_expand")

  def tool(assigns) do
    ~H"""
    <.cell cell={Builder.block(@block)} />
    """
  end
end
