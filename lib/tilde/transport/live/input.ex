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
  attr(:keydown_event, :string, default: nil)

  def input(assigns) do
    ~H"""
    <form class="input" phx-submit={@submit_event} phx-change={@change_event}>
      <textarea name="input" rows="1" placeholder={@placeholder} phx-keydown={@keydown_event}>{@value}</textarea>
      <button type="submit" class="link">send</button>
      <button :if={@running?} type="button" class="link" phx-click={@interrupt_event}>
        interrupt
      </button>
    </form>
    """
  end
end
