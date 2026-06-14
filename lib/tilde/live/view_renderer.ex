defmodule Tilde.Live.ViewRenderer do
  @moduledoc """
  LiveView renderer for shared `Tilde.View.Cell` values.
  """

  use Phoenix.Component

  import Tilde.Live.Choice
  import Tilde.Live.Markdown
  import Tilde.Live.Run
  import Tilde.Live.Tool

  alias Tilde.View.Cell

  attr(:cell, Cell, required: true)

  def cell(%{cell: %Cell{kind: :message}} = assigns) do
    ~H"""
    <article class={["tilde-block", "tilde-message", "tilde-message-#{@cell.role}"]} data-role={@cell.role}>
      <div class="tilde-label">{@cell.role}</div>
      <div class="tilde-message-body">
        <.runs :if={@cell.runs != []} runs={@cell.runs} />
        <.markdown :if={@cell.runs == [] and @cell.format == :markdown} source={@cell.source} />
        <%= if @cell.runs == [] and @cell.format != :markdown do %>
          {@cell.source}
        <% end %>
      </div>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :tool}} = assigns) do
    assigns = assign(assigns, :block, assigns.cell.attrs.block)

    ~H"""
    <.tool block={@block} />
    """
  end

  def cell(%{cell: %Cell{kind: :choice}} = assigns) do
    assigns = assign(assigns, :block, assigns.cell.attrs.block)

    ~H"""
    <.choice block={@block} />
    """
  end

  def cell(%{cell: %Cell{kind: :suggest}} = assigns) do
    assigns = assign(assigns, :suggest, assigns.cell.attrs.suggest)

    ~H"""
    <section class="tilde-suggest" data-suggest-trigger={@suggest.trigger} data-suggest-query={@suggest.query}>
      <div class="tilde-suggest-title">{@suggest.title}</div>
      <div class="tilde-suggest-items">
        <button
          :for={item <- @suggest.items}
          type="button"
          class="tilde-suggest-row"
          phx-click="tilde:complete_input"
          phx-value-insert={item.insert}
        >
          <code>{item.label}</code>
          <span>{item.description}</span>
        </button>
      </div>
    </section>
    """
  end

  def cell(assigns) do
    ~H"""
    <%= for line <- @cell.lines do %>
      <div>{line}</div>
    <% end %>
    """
  end
end
