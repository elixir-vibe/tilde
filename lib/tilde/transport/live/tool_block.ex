defmodule Tilde.Transport.Live.ToolBlock do
  @moduledoc """
  LiveView renderer for tool cells using the shared panel anatomy.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Controls
  import Tilde.Transport.Live.Line
  import Tilde.Transport.Live.Panel

  alias Tilde.View.{Cell, Line}

  attr(:cell, Cell, required: true)

  def tool_block(assigns) do
    assigns =
      assigns
      |> assign(:view, assigns.cell.attrs.view)
      |> assign(:syntax_html, Tilde.Transport.Live.ReadTool.syntax_html(assigns.cell.attrs.view))
      |> assign(:body_lines, body_lines(assigns.cell, assigns.cell.attrs.view))

    ~H"""
    <.panel
      id={@cell.id}
      kind="tool"
      state={@view.status}
      expandable?={expandable?(@view)}
      expand_key="ctrl+o"
    >
      <:header>
        <span class="call"><.line line={List.first(@cell.lines)} /></span>
      </:header>

      <:body>
        <div :if={@syntax_html} class="lines syntax">
          {Phoenix.HTML.raw(@syntax_html)}
        </div>

        <div :if={!@syntax_html && @body_lines != []} class="lines">
          <div :for={line <- @body_lines} class={["line", line_role(line)]}><.line line={line} /></div>
        </div>
      </:body>

      <:footer :if={expandable?(@view)}>
        <span :if={@view.hidden_lines > 0} class="muted">… {@view.hidden_lines} {@view.hidden_unit || "more lines"}</span>
        <.action
          event="tilde:toggle_expand"
          label={if @view.expanded?, do: "collapse", else: "expand"}
          key={if @view.expanded?, do: nil, else: "ctrl+o"}
          values={%{"phx-value-id" => @cell.id}}
        />
      </:footer>
    </.panel>
    """
  end

  defp body_lines(%Cell{lines: [_header | body]}, view) do
    if expandable?(view), do: Enum.drop(body, -1), else: body
  end

  defp body_lines(_cell, _view), do: []

  defp expandable?(%{expanded?: true}), do: true
  defp expandable?(%{hidden_lines: hidden}), do: hidden > 0

  defp line_role(%Line{role: role}), do: role
  defp line_role(_line), do: nil
end
