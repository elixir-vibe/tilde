defmodule Tilde.Transport.Live.ViewRenderer do
  @moduledoc """
  LiveView renderer for shared `Tilde.View.Cell` values.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Markdown
  import Tilde.Transport.Live.Run
  import Tilde.Transport.Live.Shortcut

  alias Tilde.View.{Cell, Helpers, Line, Text}

  attr(:cell, Cell, required: true)

  def cell(%{cell: %Cell{kind: :message}} = assigns) do
    ~H"""
    <article class={["block", "message", "message-#{@cell.role}"]} data-role={@cell.role}>
      <div class="label">{@cell.role}</div>
      <div class="message-body">
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
    assigns =
      assigns
      |> assign(:view, assigns.cell.attrs.view)
      |> assign(:body_lines, tool_body_lines(assigns.cell, assigns.cell.attrs.view))

    ~H"""
    <article
      id={@cell.id}
      class={["block", "tool", "is-#{@view.status}"]}
      data-block-id={@cell.id}
      data-expand-key="ctrl+o"
      tabindex="0"
    >
      <header class="tool-header">
        <span class="tool-call"><.view_line line={List.first(@cell.lines)} /></span>
      </header>

      <div :if={@body_lines != []} class="tool-cell-lines">
        <div :for={line <- @body_lines} class="tool-cell-line"><.view_line line={line} /></div>
      </div>

      <footer :if={tool_expandable?(@view)} class="tool-footer">
        <span :if={@view.hidden_lines > 0} class="muted">… {@view.hidden_lines} more lines</span>
        <button
          type="button"
          class="link-button"
          phx-click="tilde:toggle_expand"
          phx-value-id={@cell.id}
        >
          <%= if @view.expanded? do %>
            collapse
          <% else %>
            <.shortcut key="ctrl+o" label="expand" />
          <% end %>
        </button>
      </footer>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :choice}} = assigns) do
    assigns =
      assigns
      |> assign(:choice, assigns.cell.attrs.choice)
      |> assign(:question, List.first(assigns.cell.lines) || Helpers.line(""))
      |> assign(:option_lines, Enum.drop(assigns.cell.lines, 1))

    ~H"""
    <article id={@cell.id} class="block choice" data-block-id={@cell.id} tabindex="0">
      <div class="choice-question"><.view_line line={@question} /></div>

      <div class="choice-options">
        <button
          :for={{option, line} <- Enum.zip(@choice.options, @option_lines)}
          type="button"
          class={["choice-option", option.id in @choice.selected && "is-selected"]}
          phx-click="tilde:select_choice"
          phx-value-block-id={@cell.id}
          phx-value-option-id={option.id}
        >
          <.view_line line={line} />
        </button>
      </div>

      <footer class="choice-actions">
        <button
          :for={action <- @choice.actions}
          type="button"
          class={["action", "action-#{action.kind}"]}
          phx-click="tilde:choice_action"
          phx-value-block-id={@cell.id}
          phx-value-action-id={action.id}
        >
          {action.label}<.shortcut :if={action.key} key={action.key} />
        </button>
      </footer>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :suggest}} = assigns) do
    assigns = assign(assigns, :suggest, assigns.cell.attrs.suggest)

    ~H"""
    <section class="suggest" data-suggest-trigger={@suggest.trigger} data-suggest-query={@suggest.query}>
      <div class="suggest-title">{@suggest.title}</div>
      <div class="suggest-items">
        <button
          :for={{item, index} <- Enum.with_index(@suggest.items)}
          type="button"
          class={["suggest-row", index == @suggest.selected_index && "is-selected"]}
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
      <div><.view_line line={line} /></div>
    <% end %>
    """
  end

  attr(:line, :any, required: true)

  def view_line(%{line: %Line{} = line} = assigns) do
    assigns = assign(assigns, :parts, line.parts)

    ~H"""
    <.view_part :for={part <- @parts} part={part} />
    """
  end

  def view_line(%{line: :blank} = assigns) do
    ~H"""
    <br />
    """
  end

  def view_line(assigns) do
    ~H"""
    {@line}
    """
  end

  attr(:part, Text, required: true)

  def view_part(assigns) do
    ~H"""
    <span class={"text-#{@part.style}"}>{@part.text}</span>
    """
  end

  defp tool_body_lines(%Cell{lines: [_header | body]}, view) do
    if tool_expandable?(view), do: Enum.drop(body, -1), else: body
  end

  defp tool_body_lines(_cell, _view), do: []

  defp tool_expandable?(%{expanded?: true}), do: true
  defp tool_expandable?(%{hidden_lines: hidden}), do: hidden > 0
end
