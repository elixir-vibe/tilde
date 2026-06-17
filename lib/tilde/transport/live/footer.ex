defmodule Tilde.Transport.Live.Footer do
  @moduledoc """
  Minimal footer/statusline component.
  """

  use Phoenix.Component

  attr(:session, :any, default: nil)
  attr(:left, :string, default: "")
  attr(:right, :string, default: "")

  def footer(assigns) do
    assigns =
      assigns
      |> assign(:session_text, session_text(assigns.session))
      |> assign(:status_text, status_text(assigns.session))

    ~H"""
    <footer class="tilde-footer">
      <span>{@left}</span>
      <span class="tilde-muted">
        <span :if={@session_text != ""}>{@session_text}</span>
        <span :if={@session_text != "" and @status_text != ""}> · </span>
        <span :if={@status_text != ""}>{@status_text}</span>
      </span>
      <span>{@right}</span>
    </footer>
    """
  end

  defp session_text(nil), do: ""
  defp session_text(%{id: id}) when is_binary(id), do: "session: #{id}"
  defp session_text(_session), do: ""

  defp status_text(nil), do: ""
  defp status_text(%{statuses: statuses}) when map_size(statuses) == 0, do: ""

  defp status_text(%{statuses: statuses}) do
    statuses
    |> Enum.map_join(" · ", fn {key, value} -> "#{key}: #{value}" end)
  end
end
