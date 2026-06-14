defmodule Tilde.Live.Message do
  @moduledoc """
  LiveView component for semantic message blocks.
  """

  use Phoenix.Component

  attr(:block, :any, required: true)

  def message(assigns) do
    ~H"""
    <article class={["tilde-block", "tilde-message", "tilde-message-#{@block.role}"]} data-role={@block.role}>
      <div class="tilde-label">{@block.role}</div>
      <div class="tilde-message-body">
        {render_source(@block.source)}
      </div>
    </article>
    """
  end

  defp render_source(source) when is_binary(source), do: source
end
