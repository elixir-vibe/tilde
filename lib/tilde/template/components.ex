defmodule Tilde.Template.Components do
  @moduledoc """
  Tilde-native semantic HEEx component names.

  `Tilde.Template` reads these component names from Phoenix's HEEx source AST and
  maps them directly to `Tilde.View.Cell`, `Tilde.View.Line`, and
  `Tilde.View.Text`. The function bodies are also valid Phoenix components for
  editor tooling and ordinary HEEx previews, but Tilde's semantic template path
  does not parse rendered HTML.
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

  attr(:role, :string, default: "assistant")
  attr(:format, :string, default: "plain")
  slot(:inner_block, required: true)

  def message(assigns) do
    ~H"""
    <article data-tilde-message="true" data-tilde-role={@role} data-tilde-format={@format}>{render_slot(@inner_block)}</article>
    """
  end

  attr(:role, :string, default: "assistant")
  slot(:inner_block, required: true)

  def markdown(assigns) do
    ~H"""
    <article data-tilde-message="true" data-tilde-role={@role} data-tilde-format="markdown">{render_slot(@inner_block)}</article>
    """
  end

  attr(:state, :string, default: "normal")
  attr(:padding_x, :integer, default: 1)
  attr(:padding_y, :integer, default: 1)
  slot(:inner_block, required: true)

  def tool(assigns) do
    ~H"""
    <section data-tilde-tool="true" data-tilde-state={@state} data-tilde-padding-x={@padding_x} data-tilde-padding-y={@padding_y}>{render_slot(@inner_block)}</section>
    """
  end

  attr(:state, :string, default: "normal")
  slot(:inner_block, required: true)

  def choice(assigns) do
    ~H"""
    <section data-tilde-choice="true" data-tilde-state={@state}>{render_slot(@inner_block)}</section>
    """
  end

  slot(:inner_block, required: true)

  def suggest(assigns) do
    ~H"""
    <section data-tilde-suggest="true">{render_slot(@inner_block)}</section>
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

  slot(:inner_block, required: true)
  def code(assigns), do: styled(assigns, "accent")

  slot(:inner_block, required: true)

  def item(assigns) do
    ~H"""
    <div data-tilde-line="true" data-tilde-role="normal">• {render_slot(@inner_block)}</div>
    """
  end

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
