defmodule Tilde.Transport.Live.Footer do
  @moduledoc """
  Minimal footer/statusline component.
  """

  use Phoenix.Component

  attr(:session, :any, default: nil)
  attr(:left, :string, default: "")
  attr(:right, :string, default: "")
  attr(:commands, :list, default: [])
  attr(:devtools?, :boolean, default: false)
  attr(:dev_grid?, :boolean, default: false)
  attr(:dev_raw, :string, default: "")

  def footer(assigns) do
    assigns =
      assigns
      |> assign(:session_text, session_text(assigns.session))
      |> assign(:status_text, status_text(assigns.session))

    ~H"""
    <footer class="footer">
      <div class="left muted">
        <span :if={@left != ""}>{@left}</span>
        <span :if={@left != "" and @session_text != ""}> · </span>
        <span :if={@session_text != ""}>{@session_text}</span>
        <span :if={(@left != "" or @session_text != "") and @status_text != ""}> · </span>
        <span :if={@status_text != ""}>{@status_text}</span>
      </div>
      <div class="right">
        <span :if={@right != ""}>{@right}</span>
        <span :if={@commands != []} class="actions" role="navigation" aria-label="commands">
          <%= for {command, index} <- Enum.with_index(@commands) do %>
            <a
              href="#"
              class="action normal"
              phx-click="tilde:complete_input"
              phx-value-insert={command.insert}
            >{command.label}</a><span :if={index < length(@commands) - 1}> · </span>
          <% end %>
        </span>
        <.devtools enabled?={@devtools?} grid?={@dev_grid?} raw={@dev_raw} />
      </div>
    </footer>
    """
  end

  attr(:enabled?, :boolean, required: true)
  attr(:grid?, :boolean, required: true)
  attr(:raw, :string, default: "")

  defp devtools(assigns) do
    ~H"""
    <nav :if={@enabled?} id="tilde-devtools" class="dev" aria-label="development tools" phx-hook="TildeDevtools">
      <button
        class="button"
        type="button"
        phx-click="tilde:dev_toggle_grid"
        aria-pressed={@grid?}
        aria-describedby="tilde-dev-tooltip"
      >
        [dev]
      </button>
      <pre id="tilde-dev-tooltip" class="tooltip" role="tooltip" data-raw={@raw}></pre>
    </nav>
    """
  end

  defp session_text(nil), do: ""
  defp session_text(%{id: id}) when is_binary(id), do: "session: #{id}"
  defp session_text(_session), do: ""

  defp status_text(nil), do: ""
  defp status_text(%{statuses: statuses}) when map_size(statuses) == 0, do: ""

  defp status_text(%{statuses: statuses}) do
    Enum.map_join(statuses, " · ", fn {key, value} -> "#{key}: #{value}" end)
  end
end
