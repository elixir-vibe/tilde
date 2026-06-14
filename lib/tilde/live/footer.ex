defmodule Tilde.Live.Footer do
  @moduledoc """
  Minimal footer/statusline component.
  """

  use Phoenix.Component

  attr(:session, :any, default: nil)
  attr(:left, :string, default: "")
  attr(:right, :string, default: "")

  def footer(assigns) do
    assigns = assign(assigns, :status_text, status_text(assigns.session))

    ~H"""
    <footer class="tilde-footer">
      <span>{@left}</span>
      <span :if={@status_text != ""} class="tilde-muted">{@status_text}</span>
      <span>{@right}</span>
    </footer>
    """
  end

  defp status_text(nil), do: ""
  defp status_text(%{statuses: statuses}) when map_size(statuses) == 0, do: ""

  defp status_text(%{statuses: statuses}) do
    statuses
    |> Enum.map_join(" · ", fn {key, value} -> "#{key}: #{value}" end)
  end
end
