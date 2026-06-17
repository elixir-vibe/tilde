defmodule Tilde.Transport.Live.WidgetRenderer do
  @moduledoc "LiveView renderer for semantic `Tilde.Core.Widget` trees."

  use Phoenix.Component

  import Tilde.Transport.Live.Footer
  import Tilde.Transport.Live.Input
  import Tilde.Transport.Live.Shortcut
  import Tilde.Transport.Live.ViewRenderer

  alias Tilde.Core.{Input, Widget}

  attr(:widgets, :list, required: true)

  def widgets(assigns) do
    ~H"""
    <.widget :for={widget <- @widgets} widget={widget} />
    """
  end

  attr(:widget, Widget, required: true)

  def widget(%{widget: %Widget{kind: :screen}} = assigns) do
    assigns = assign(assigns, :class, assigns.widget.metadata[:class])

    ~H"""
    <main id={@widget.id} class={["tilde", @class]} phx-hook="TildeConsole">
      <.widget :for={child <- @widget.children} widget={child} />
    </main>
    """
  end

  def widget(%{widget: %Widget{kind: :section}} = assigns) do
    ~H"""
    <section id={@widget.id} class="widgets" data-placement={@widget.placement}>
      <.widget :for={child <- @widget.children} widget={child} />
    </section>
    """
  end

  def widget(%{widget: %Widget{kind: kind}} = assigns) when kind in [:heading, :text, :muted] do
    ~H"""
    <section class="transcript" id={if @widget.kind == :heading, do: "tilde-transcript", else: nil}>
      <article class={["block", "message", "system"]} data-role="system">
        <div class={["body", @widget.kind == :muted && "muted"]}>{@widget.content}</div>
      </article>
    </section>
    """
  end

  def widget(%{widget: %Widget{kind: :suggest}} = assigns) do
    ~H"""
    <section class="widgets" data-placement={@widget.placement}>
      <aside id={@widget.id} class="widget" data-placement={@widget.placement}>
        <.cell cell={Tilde.Viewable.to_view(@widget)} />
      </aside>
    </section>
    """
  end

  def widget(%{widget: %Widget{kind: :input, content: %Input{} = input}} = assigns) do
    assigns = assign(assigns, :input, input)

    ~H"""
    <section class="dock">
      <.input value={@input.value} running?={false} keydown_event="tilde:index_keydown" />
    </section>
    """
  end

  def widget(%{widget: %Widget{kind: :shortcut_bar}} = assigns) do
    ~H"""
    <section class="shortcuts">
      <.shortcut :for={shortcut <- @widget.content} key={shortcut.key} label={shortcut.label} />
    </section>
    """
  end

  def widget(%{widget: %Widget{kind: :footer}} = assigns) do
    ~H"""
    <.footer session={nil} left={@widget.content.left} right={@widget.content.right} />
    """
  end

  def widget(assigns) do
    ~H"""
    <section id={@widget.id} class="widget"><%= inspect(@widget.content) %></section>
    """
  end
end
