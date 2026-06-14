defmodule Tilde.Live.Markdown do
  @moduledoc """
  LiveView component for Markdown source content.
  """

  use Phoenix.Component

  alias Tilde.Markdown

  attr(:source, :string, required: true)
  attr(:options, :list, default: [])

  def markdown(assigns) do
    assigns = assign(assigns, :rendered, Markdown.to_html(assigns.source, assigns.options))

    ~H"""
    <div class="tilde-markdown">
      <%= case @rendered do %>
        <% {:ok, html} -> %>
          {Phoenix.HTML.raw(html)}
        <% {:error, :mdex_not_available} -> %>
          <div class="tilde-plain-text">{@source}</div>
      <% end %>
    </div>
    """
  end
end
