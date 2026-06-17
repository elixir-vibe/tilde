defmodule Tilde.Transport.Live.Shortcut do
  @moduledoc """
  Shared LiveView shortcut hint component.
  """

  use Phoenix.Component

  attr(:key, :string, required: true)
  attr(:label, :string, default: nil)
  attr(:class, :any, default: nil)

  def shortcut(assigns) do
    ~H"""
    <span class={["shortcut", @class]}>
      <kbd class="key">{@key}</kbd>
      <span :if={@label} class="label">{@label}</span>
    </span>
    """
  end
end
