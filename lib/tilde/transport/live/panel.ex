defmodule Tilde.Transport.Live.Panel do
  @moduledoc """
  Shared LiveView shell for block-like console panels.

  The panel owns the repeated article/header/body/footer anatomy used by tool,
  choice, and related transcript blocks while each block renderer owns its
  domain-specific content.
  """

  use Phoenix.Component

  attr(:id, :string, required: true)
  attr(:kind, :string, required: true)
  attr(:state, :any, default: nil)
  attr(:class, :any, default: nil)
  attr(:expandable?, :boolean, default: false)
  attr(:expand_key, :string, default: nil)
  attr(:rest, :global)

  slot(:header, required: true)
  slot(:body)
  slot(:footer)

  def panel(assigns) do
    assigns = assign(assigns, :classes, classes(assigns.kind, assigns.state, assigns.class))

    ~H"""
    <article
      id={@id}
      class={@classes}
      data-block-id={@id}
      data-expandable={@expandable?}
      data-expand-key={@expand_key}
      tabindex="0"
      {@rest}
    >
      <header class="header">{render_slot(@header)}</header>
      {render_slot(@body)}
      <footer :if={@footer != []} class="footer actions">{render_slot(@footer)}</footer>
    </article>
    """
  end

  defp classes(kind, state, extra) do
    ["block", kind, state | List.wrap(extra)]
    |> Enum.reject(&(&1 in [nil, false, ""]))
    |> Enum.map(&to_string/1)
  end
end
