defmodule Tilde.Transport.Live.ViewRenderer do
  @moduledoc """
  LiveView renderer for shared `Tilde.View.Cell` values.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Controls
  import Tilde.Transport.Live.Markdown
  import Tilde.Transport.Live.Run

  alias Tilde.View.{Cell, Helpers, Line, Text}

  attr(:cell, Cell, required: true)

  def cell(%{cell: %Cell{kind: :message}} = assigns) do
    ~H"""
    <article class={["block", "message", @cell.role]} data-role={@cell.role}>
      <div class="label">{@cell.role}</div>
      <div class="body">
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
      class={["block", "tool", @view.status]}
      data-block-id={@cell.id}
      data-expandable={tool_expandable?(@view)}
      data-expand-key="ctrl+o"
      tabindex="0"
    >
      <header class="header">
        <span class="call"><.view_line line={List.first(@cell.lines)} /></span>
      </header>

      <div :if={@body_lines != []} class="lines">
        <div :for={line <- @body_lines} class={["line", line_role(line)]}><.view_line line={line} /></div>
      </div>

      <footer :if={tool_expandable?(@view)} class="footer actions">
        <span :if={@view.hidden_lines > 0} class="muted">… {@view.hidden_lines} {@view.hidden_unit || "more lines"}</span>
        <.action
          event="tilde:toggle_expand"
          label={if @view.expanded?, do: "collapse", else: "expand"}
          key={if @view.expanded?, do: nil, else: "ctrl+o"}
          values={%{"phx-value-id" => @cell.id}}
        />
      </footer>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :choice}} = assigns) do
    assigns =
      assigns
      |> assign(:choice, assigns.cell.attrs.choice)
      |> assign(:question, List.first(assigns.cell.lines) || Helpers.line(""))

    ~H"""
    <article id={@cell.id} class="block choice" data-block-id={@cell.id} tabindex="0">
      <div class="question"><.view_line line={@question} /></div>

      <div class="options">
        <button
          :for={option <- @choice.options}
          type="button"
          class={["option", option.id in @choice.selected && "selected"]}
          phx-click="tilde:select_choice"
          phx-value-block-id={@cell.id}
          phx-value-option-id={option.id}
        >
          <span class="marker">{if option.id in @choice.selected, do: "[x]", else: "[ ]"}</span>
          <span>{option.label}</span>
          <span :if={option[:description]} class="description">— {option.description}</span>
        </button>
      </div>

      <footer class="actions">
        <.action
          :for={action <- @choice.actions}
          event="tilde:choice_action"
          label={action.label}
          key={action.key}
          kind={action.kind}
          values={%{"phx-value-block-id" => @cell.id, "phx-value-action-id" => action.id}}
        />
      </footer>
    </article>
    """
  end

  def cell(%{cell: %Cell{kind: :suggest}} = assigns) do
    assigns = assign(assigns, :suggest, assigns.cell.attrs.suggest)

    ~H"""
    <section class="suggest" data-suggest-trigger={@suggest.trigger} data-suggest-query={@suggest.query}>
      <div class="title">{@suggest.title}</div>
      <div class="items">
        <button
          :for={{item, index} <- Enum.with_index(@suggest.items)}
          type="button"
          class={["row", index == @suggest.selected_index && "selected"]}
          phx-click="tilde:complete_input"
          phx-value-insert={item.insert}
          aria-describedby={item.detail && "#{@suggest.id}-detail-#{index}"}
        >
          <span class="marker" aria-hidden="true">
            <%= if index == @suggest.selected_index, do: "›", else: "" %>
          </span>
          <code class="command">{item.label}</code>
          <span class="description">{item.description}</span>
          <span :if={item.detail} id={"#{@suggest.id}-detail-#{index}"} class="detail" role="tooltip">
            {item.detail}
          </span>
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

  defp line_role(%Line{role: role}), do: role
  defp line_role(_line), do: nil

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
    <span class={["text", @part.style]}>{@part.text}</span>
    """
  end

  defp tool_body_lines(%Cell{lines: [_header | body]}, view) do
    if tool_expandable?(view), do: Enum.drop(body, -1), else: body
  end

  defp tool_body_lines(_cell, _view), do: []

  defp tool_expandable?(%{expanded?: true}), do: true
  defp tool_expandable?(%{hidden_lines: hidden}), do: hidden > 0
end
