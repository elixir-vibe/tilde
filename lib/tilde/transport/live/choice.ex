defmodule Tilde.Transport.Live.Choice do
  @moduledoc """
  Compatibility component for semantic choice blocks.

  New rendering goes through the shared `Tilde.View` cell pipeline so LiveView,
  TUI, and SSH stay aligned.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.ViewRenderer

  attr(:block, :any, required: true)
  attr(:select_event, :string, default: "tilde:select_choice")
  attr(:action_event, :string, default: "tilde:choice_action")

  def choice(assigns) do
    ~H"""
    <.cell cell={Tilde.Viewable.to_view(@block)} />
    """
  end
end
