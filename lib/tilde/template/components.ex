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

  attr(:id, :string, default: "screen")
  attr(:class, :string, default: nil)
  slot(:inner_block, required: true)

  def screen(assigns) do
    ~H"""
    <section data-tilde-widget="screen" data-tilde-id={@id} data-tilde-class={@class}>{render_slot(@inner_block)}</section>
    """
  end

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  slot(:inner_block, required: true)

  def section(assigns) do
    ~H"""
    <section data-tilde-widget="section" data-tilde-id={@id} data-tilde-title={@title}>{render_slot(@inner_block)}</section>
    """
  end

  attr(:id, :string, required: true)
  attr(:text, :string, required: true)
  attr(:kind, :string, default: "text")

  def widget_text(assigns) do
    ~H"""
    <span data-tilde-widget="text" data-tilde-id={@id} data-tilde-kind={@kind}>{@text}</span>
    """
  end

  attr(:id, :string, required: true)
  attr(:suggest, :any, required: true)
  def widget_suggest(assigns), do: assigns |> assign(:_unused, nil) |> raw_widget()

  attr(:id, :string, required: true)
  attr(:input, :any, required: true)
  def widget_input(assigns), do: assigns |> assign(:_unused, nil) |> raw_widget()

  attr(:id, :string, required: true)
  attr(:shortcuts, :list, required: true)
  def shortcut_bar(assigns), do: assigns |> assign(:_unused, nil) |> raw_widget()

  attr(:id, :string, required: true)
  attr(:right, :string, default: "")
  attr(:commands, :list, default: [])
  def widget_footer(assigns), do: assigns |> assign(:_unused, nil) |> raw_widget()

  attr(:id, :string, required: true)
  attr(:title, :string, required: true)
  attr(:body, :string, default: "")
  attr(:actions, :list, default: [])
  def dialog(assigns), do: assigns |> assign(:_unused, nil) |> raw_widget()

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
    <span class={["text", @style]}>{render_slot(@inner_block)}</span>
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
  attr(:tags, :list, default: [])
  attr(:suffix, :string, default: nil)

  def tool_call(assigns) do
    ~H"""
    <div data-tilde-line="true" data-tilde-role="title">
      <span class="text title">{@name}</span><span :if={@segment} class="text accent"> {@segment}</span><span :if={@tags != []} class="text muted"> [{Enum.join(@tags, ", ")}]</span><span :if={@suffix} class="text muted"> ({@suffix})</span>
    </div>
    """
  end

  defp raw_widget(assigns) do
    ~H"""
    <span data-tilde-widget={@id}></span>
    """
  end

  defp styled(assigns, style) do
    assigns = assign(assigns, :style, style)

    ~H"""
    <span class={["text", @style]}>{render_slot(@inner_block)}</span>
    """
  end
end
