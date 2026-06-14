defmodule Tilde.Live.Tool do
  @moduledoc """
  LiveView component for semantic tool blocks.
  """

  use Phoenix.Component

  alias Tilde.ToolView

  attr(:block, :any, required: true)
  attr(:toggle_event, :string, default: "tilde:toggle_expand")

  def tool(assigns) do
    assigns = assign(assigns, :view, ToolView.view(assigns.block))

    ~H"""
    <article
      id={@block.id}
      class={["tilde-block", "tilde-tool", "tilde-tool-#{@view.status}"]}
      data-block-id={@block.id}
      data-expand-key="ctrl+o"
      tabindex="0"
    >
      <header class="tilde-tool-header">
        <span class="tilde-tool-name">{@view.name}</span>
        <span :if={@view.arg_summary != ""} class="tilde-tool-args">{@view.arg_summary}</span>
        <span class="tilde-tool-status">{@view.status}</span>
      </header>

      <dl :if={@view.metadata_rows != []} class="tilde-tool-metadata">
        <div :for={{key, value} <- @view.metadata_rows}>
          <dt>{key}</dt>
          <dd>{value}</dd>
        </div>
      </dl>

      <div :if={@view.streams != []} class="tilde-tool-streams">
        <section
          :for={stream <- @view.streams}
          :if={stream.lines != [] or stream.hidden_lines > 0}
          class={["tilde-tool-stream", "tilde-tool-stream-#{stream.kind}"]}
          data-stream-kind={stream.kind}
        >
          <div :if={length(@view.streams) > 1} class="tilde-tool-stream-label">{stream.kind}</div>
          <pre :if={stream.lines != []}><%= Enum.join(stream.lines, "\n") %></pre>
          <div :if={stream.hidden_lines > 0} class="tilde-muted">… {stream.hidden_lines} more {stream.kind} lines</div>
        </section>
      </div>

      <footer :if={@view.hidden_lines > 0 or expandable?(@view)} class="tilde-tool-footer">
        <span :if={@view.hidden_lines > 0} class="tilde-muted">… {@view.hidden_lines} more lines</span>
        <button
          type="button"
          class="tilde-link-button"
          phx-click={@toggle_event}
          phx-value-id={@block.id}
        >
          {if @view.expanded?, do: "collapse", else: "ctrl+o to expand"}
        </button>
      </footer>
    </article>
    """
  end

  defp expandable?(%{expanded?: true}), do: true
  defp expandable?(%{hidden_lines: hidden}), do: hidden > 0
end
