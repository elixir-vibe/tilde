defmodule Tilde.Transport.Live.Input do
  @moduledoc """
  Minimal semantic console input component.
  """

  use Phoenix.Component

  attr(:value, :string, default: "")
  attr(:placeholder, :string, default: "Message…")
  attr(:submit_event, :string, default: "tilde:submit")
  attr(:change_event, :string, default: "tilde:input_changed")
  attr(:interrupt_event, :string, default: "tilde:interrupt")
  attr(:running?, :boolean, default: false)

  def input(assigns) do
    ~H"""
    <form class="tilde-input" phx-submit={@submit_event} phx-change={@change_event}>
      <textarea name="input" rows="1" placeholder={@placeholder}>{@value}</textarea>
      <button type="submit" class="tilde-link-button">send</button>
      <button :if={@running?} type="button" class="tilde-link-button" phx-click={@interrupt_event}>
        interrupt
      </button>
    </form>
    """
  end
end
