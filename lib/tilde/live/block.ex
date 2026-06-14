defmodule Tilde.Live.Block do
  @moduledoc """
  Dispatcher component for semantic transcript blocks.
  """

  use Phoenix.Component

  import Tilde.Live.Choice
  import Tilde.Live.Message
  import Tilde.Live.Tool

  attr(:block, :any, required: true)

  def block(assigns) do
    ~H"""
    <%= case @block.kind do %>
      <% :message -> %>
        <.message block={@block} />
      <% :tool -> %>
        <.tool block={@block} />
      <% :choice -> %>
        <.choice block={@block} />
      <% _other -> %>
        <article class="tilde-block tilde-unknown" data-kind={@block.kind}>{inspect(@block.kind)}</article>
    <% end %>
    """
  end
end
