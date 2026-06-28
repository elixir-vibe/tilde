defmodule Tilde.Transport.Live.Controls do
  @moduledoc "Shared LiveView controls."

  use Phoenix.Component

  import Tilde.Transport.Live.Shortcut

  alias Tilde.Core.Shortcuts

  attr(:event, :string, default: nil)
  attr(:label, :string, required: true)
  attr(:key, :string, default: nil)
  attr(:shortcut, :string, default: nil)
  attr(:kind, :atom, default: :normal)
  attr(:values, :map, default: %{})

  def action(assigns) do
    assigns =
      assign(assigns, :display_key, assigns.key || Shortcuts.display_key(assigns.shortcut))

    ~H"""
    <button type="button" class={["action", @kind]} phx-click={@event} {@values}>
      <.shortcut :if={@display_key} key={@display_key} label={@label} />
      <span :if={!@display_key}>{@label}</span>
    </button>
    """
  end
end
