defmodule Tilde.Transport.Live.Controls do
  @moduledoc "Shared LiveView controls."

  use Phoenix.Component

  import Tilde.Transport.Live.Shortcut

  attr(:event, :string, default: nil)
  attr(:label, :string, required: true)
  attr(:key, :string, default: nil)
  attr(:kind, :atom, default: :normal)
  attr(:values, :map, default: %{})

  def action(assigns) do
    ~H"""
    <button type="button" class={["action", @kind]} phx-click={@event} {@values}>
      <.shortcut :if={@key} key={@key} label={@label} />
      <span :if={!@key}>{@label}</span>
    </button>
    """
  end
end
