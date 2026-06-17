defmodule Tilde.Transport.Live.Run do
  @moduledoc """
  LiveView components for semantic inline runs.
  """

  use Phoenix.Component

  alias Tilde.Core.Run

  attr(:runs, :list, required: true)

  def runs(assigns) do
    ~H"""
    <.run :for={run <- @runs} run={run} />
    """
  end

  attr(:run, :any, required: true)

  def run(assigns) do
    ~H"""
    <%= if link?(@run) do %>
      <a class={classes(@run)} href={@run.attrs.href}><.marked run={@run} /></a>
    <% else %>
      <span class={classes(@run)}><.marked run={@run} /></span>
    <% end %>
    """
  end

  attr(:run, :any, required: true)

  def marked(assigns) do
    ~H"""
    <%= cond do %>
      <% code?(@run) -> %>
        <code><.marked_text run={without_mark(@run, :code)} /></code>
      <% bold?(@run) -> %>
        <strong><.marked_text run={without_mark(@run, :bold)} /></strong>
      <% italic?(@run) -> %>
        <em><.marked_text run={without_mark(@run, :italic)} /></em>
      <% underline?(@run) -> %>
        <u><.marked_text run={without_mark(@run, :underline)} /></u>
      <% strike?(@run) -> %>
        <s><.marked_text run={without_mark(@run, :strike)} /></s>
      <% true -> %>
        {@run.text}
    <% end %>
    """
  end

  attr(:run, :any, required: true)

  def marked_text(assigns) do
    ~H"""
    <.marked run={@run} />
    """
  end

  defp classes(%Run{marks: marks}) do
    Enum.map(marks, &"tilde-run-#{&1}")
  end

  defp link?(%Run{attrs: %{href: href}}) when is_binary(href), do: true
  defp link?(_run), do: false

  defp code?(%Run{marks: marks}), do: :code in marks
  defp bold?(%Run{marks: marks}), do: :bold in marks
  defp italic?(%Run{marks: marks}), do: :italic in marks
  defp underline?(%Run{marks: marks}), do: :underline in marks
  defp strike?(%Run{marks: marks}), do: :strike in marks

  defp without_mark(%Run{} = run, mark), do: %{run | marks: List.delete(run.marks, mark)}
end
