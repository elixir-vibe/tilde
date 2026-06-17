defmodule Tilde.Renderer.TUI.WidgetRenderer do
  @moduledoc "Projects semantic widgets to terminal text."

  alias Tilde.Core.{Input, Widget}
  alias Tilde.Renderer.TUI.{Theme, ViewRenderer}

  @spec render([Widget.t()] | Widget.t(), pos_integer(), keyword()) :: String.t()
  def render(widgets_or_widget, width, opts \\ [])

  def render(widgets, width, opts) when is_list(widgets) do
    widgets
    |> Enum.map(&render(&1, width, opts))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def render(%Widget{kind: :screen} = widget, width, opts) do
    widget.children
    |> Enum.map(&render(&1, width, opts))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  def render(%Widget{kind: :section} = widget, width, opts) do
    widget.children
    |> Enum.map(&render(&1, width, opts))
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> Theme.muted(widget.content, opts)
      children -> Enum.join(children, "\n")
    end
  end

  def render(%Widget{kind: :heading, content: text}, _width, opts),
    do: Theme.title("# #{text}", opts)

  def render(%Widget{kind: :muted, content: text}, _width, opts), do: Theme.muted(text, opts)
  def render(%Widget{kind: :text, content: text}, _width, _opts), do: text

  def render(%Widget{kind: :suggest} = widget, width, opts) do
    widget |> Tilde.Viewable.to_view() |> ViewRenderer.render(width, opts)
  end

  def render(%Widget{kind: :input, content: %Input{} = input}, _width, opts) do
    render_input(input, opts)
  end

  def render(%Widget{kind: :shortcut_bar, content: shortcuts}, _width, opts) do
    shortcuts
    |> Enum.map_join(" · ", fn shortcut -> "#{shortcut.key} #{shortcut.label}" end)
    |> Theme.muted(opts)
  end

  def render(%Widget{kind: :footer, content: content}, _width, opts) do
    [content.left, content.right]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" · ")
    |> Theme.muted(opts)
  end

  def render(%Widget{content: content}, _width, _opts), do: inspect(content)

  defp render_input(%Input{} = input, opts) do
    value = input.value
    cursor = min(input.cursor, String.length(value))
    {left, right} = value |> String.graphemes() |> Enum.split(cursor)
    cursor = if Keyword.get(opts, :ansi, true), do: "", else: "▌"

    [Theme.accent(">", opts), " ", Enum.join(left), Theme.muted(cursor, opts), Enum.join(right)]
    |> IO.iodata_to_binary()
  end
end
