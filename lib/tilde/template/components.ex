defmodule Tilde.Template.Components do
  @moduledoc """
  HEEx components that carry Tilde semantic view intent.

  These are ordinary Phoenix function components, so they can be used from HEEx
  templates. They emit small semantic markers that `Tilde.Template` maps back to
  `Tilde.View.Cell`, `Tilde.View.Line`, and `Tilde.View.Text` before rendering to
  LiveView, TUI, SSH, or text.
  """

  use Phoenix.Component

  attr(:kind, :string, default: "template")
  attr(:role, :string, default: nil)
  attr(:state, :string, default: "normal")
  attr(:padding_x, :integer, default: 0)
  attr(:padding_y, :integer, default: 0)
  slot(:inner_block, required: true)

  def cell(assigns) do
    ~H"""
    <section
      data-tilde-cell="true"
      data-tilde-kind={@kind}
      data-tilde-role={@role}
      data-tilde-state={@state}
      data-tilde-padding-x={@padding_x}
      data-tilde-padding-y={@padding_y}
    >
      {render_slot(@inner_block)}
    </section>
    """
  end

  attr(:role, :string, default: "normal")
  slot(:inner_block, required: true)

  def line(assigns) do
    ~H"""
    <div data-tilde-line="true" data-tilde-role={@role}>{render_slot(@inner_block)}</div>
    """
  end

  attr(:style, :string, default: "plain")
  slot(:inner_block, required: true)

  def text(assigns) do
    ~H"""
    <span class={"tilde-view-text-#{@style}"}>{render_slot(@inner_block)}</span>
    """
  end

  slot(:inner_block, required: true)
  def title(assigns), do: styled(assigns, "title")

  slot(:inner_block, required: true)
  def accent(assigns), do: styled(assigns, "accent")

  slot(:inner_block, required: true)
  def primary(assigns), do: styled(assigns, "primary")

  slot(:inner_block, required: true)
  def muted(assigns), do: styled(assigns, "muted")

  slot(:inner_block, required: true)
  def meta(assigns), do: styled(assigns, "muted")

  slot(:inner_block, required: true)
  def error(assigns), do: styled(assigns, "error")

  slot(:inner_block, required: true)
  def success(assigns), do: styled(assigns, "success")

  attr(:name, :string, required: true)
  attr(:segment, :string, default: nil)
  attr(:suffix, :string, default: nil)

  def tool_call(assigns) do
    ~H"""
    <div data-tilde-line="true" data-tilde-role="title">
      <span class="tilde-view-text-title">{@name}</span><span :if={@segment} class="tilde-view-text-accent"> {@segment}</span><span :if={@suffix} class="tilde-view-text-muted"> ({@suffix})</span>
    </div>
    """
  end

  defp styled(assigns, style) do
    assigns = assign(assigns, :style, style)

    ~H"""
    <span class={"tilde-view-text-#{@style}"}>{render_slot(@inner_block)}</span>
    """
  end
end
