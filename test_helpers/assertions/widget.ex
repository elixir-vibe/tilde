defmodule TildeTest.WidgetAssertions do
  @moduledoc "Assertions for semantic `Tilde.Core.Widget` trees."

  import ExUnit.Assertions

  alias Tilde.Core.{Suggest, Widget}

  @spec assert_widget(Widget.t() | [Widget.t()], keyword()) :: Widget.t()
  def assert_widget(widgets, attrs) when is_list(attrs) do
    case find_widget(widgets, attrs) do
      %Widget{} = widget -> widget
      nil -> flunk("expected widget #{inspect(attrs)}, got: #{inspect(flatten_widgets(widgets))}")
    end
  end

  @spec refute_widget(Widget.t() | [Widget.t()], keyword()) :: Widget.t() | [Widget.t()]
  def refute_widget(widgets, attrs) when is_list(attrs) do
    if find_widget(widgets, attrs) do
      flunk("did not expect widget #{inspect(attrs)}")
    end

    widgets
  end

  @spec assert_widget_text(Widget.t() | [Widget.t()], String.t()) :: Widget.t()
  def assert_widget_text(widgets, text) when is_binary(text) do
    case Enum.find(flatten_widgets(widgets), &(&1.content == text)) do
      %Widget{} = widget -> widget
      nil -> flunk("expected widget text #{inspect(text)}")
    end
  end

  @spec assert_suggest_item(Widget.t() | [Widget.t()], String.t()) :: Widget.t()
  def assert_suggest_item(widgets, label) when is_binary(label) do
    case Enum.find(flatten_widgets(widgets), &suggest_has_item?(&1, label)) do
      %Widget{} = widget -> widget
      nil -> flunk("expected suggest item #{inspect(label)}")
    end
  end

  @spec assert_shortcut(Widget.t() | [Widget.t()], keyword()) :: Widget.t()
  def assert_shortcut(widgets, attrs) do
    case Enum.find(flatten_widgets(widgets), &shortcut_has?(&1, attrs)) do
      %Widget{} = widget -> widget
      nil -> flunk("expected shortcut #{inspect(attrs)}")
    end
  end

  defp find_widget(widgets, attrs) do
    Enum.find(flatten_widgets(widgets), fn widget ->
      Enum.all?(attrs, fn
        {:metadata, expected} -> map_subset?(widget.metadata, expected)
        {key, expected} -> Map.get(widget, key) == expected
      end)
    end)
  end

  defp flatten_widgets(%Widget{} = widget), do: [widget | flatten_widgets(widget.children)]
  defp flatten_widgets(widgets) when is_list(widgets), do: Enum.flat_map(widgets, &flatten_widgets/1)
  defp flatten_widgets(_other), do: []

  defp suggest_has_item?(%Widget{content: %Suggest{items: items}}, label),
    do: Enum.any?(items, &(&1.label == label))

  defp suggest_has_item?(_widget, _label), do: false

  defp shortcut_has?(%Widget{kind: :shortcut_bar, content: shortcuts}, attrs) when is_list(shortcuts) do
    Enum.any?(shortcuts, fn shortcut ->
      Enum.all?(attrs, fn {key, value} -> Map.get(shortcut, key) == value end)
    end)
  end

  defp shortcut_has?(_widget, _attrs), do: false

  defp map_subset?(map, expected) when is_map(map) and is_map(expected) do
    Enum.all?(expected, fn {key, value} -> Map.get(map, key) == value end)
  end
end
