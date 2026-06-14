defmodule Tilde.Live.Message do
  @moduledoc """
  LiveView component for semantic message blocks.
  """

  use Phoenix.Component

  import Tilde.Live.Markdown
  import Tilde.Live.Run

  attr(:block, :any, required: true)

  def message(assigns) do
    ~H"""
    <article class={["tilde-block", "tilde-message", "tilde-message-#{@block.role}"]} data-role={@block.role}>
      <div class="tilde-label">{@block.role}</div>
      <div class="tilde-message-body">
        <.runs :if={@block.runs != []} runs={@block.runs} />
        <.markdown :if={@block.runs == [] and @block.format == :markdown} source={@block.source} />
        <%= if @block.runs == [] and @block.format != :markdown do %>
          {render_source(@block.source)}
        <% end %>
      </div>
    </article>
    """
  end

  defp render_source(source) when is_binary(source), do: source
end
