defmodule Tilde.Transport.Live.Markdown do
  @moduledoc """
  LiveView component for Markdown source content.
  """

  use Phoenix.Component

  alias Tilde.Runtime.Markdown

  attr(:source, :string, required: true)
  attr(:options, :list, default: [streaming: true])

  def markdown(assigns) do
    assigns = assign(assigns, :rendered, Markdown.to_html(assigns.source, assigns.options))

    ~H"""
    <div class="markdown">
      <%= case @rendered do %>
        <% {:ok, html} -> %>
          {Phoenix.HTML.raw(html)}
        <% {:error, :mdex_not_available} -> %>
          <div class="plain">{@source}</div>
      <% end %>
    </div>
    """
  end
end
