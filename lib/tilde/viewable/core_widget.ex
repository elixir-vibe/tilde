defimpl Tilde.Viewable, for: Tilde.Core.Widget do
  alias Tilde.Core.{Dialog, Suggest, Widget}
  alias Tilde.View.Cell

  def to_view(widget), do: to_view(widget, [])

  def to_view(%Widget{kind: :dialog, content: %Dialog{} = dialog} = widget, _opts) do
    Cell.new(
      id: widget.id,
      kind: :dialog,
      state: :normal,
      source: dialog.body,
      lines: dialog_lines(dialog),
      actions: widget.actions,
      attrs: %{widget: widget, dialog: dialog},
      padding_x: 1,
      padding_y: 0
    )
  end

  def to_view(%Widget{content: %Suggest{} = suggest} = widget, _opts) do
    lines =
      [suggest.title] ++
        Enum.map(Enum.with_index(suggest.items), fn {item, index} ->
          marker = if index == suggest.selected_index, do: "› ", else: "  "

          marker <>
            item.label <>
            String.duplicate(" ", max(1, 12 - String.length(item.label))) <> item.description
        end) ++ selected_detail_lines(suggest)

    Cell.new(
      id: widget.id,
      kind: :suggest,
      state: :normal,
      lines: lines,
      attrs: %{widget: widget, suggest: suggest}
    )
  end

  def to_view(%Widget{content: content} = widget, _opts) when is_binary(content) do
    Cell.new(
      id: widget.id,
      kind: :widget,
      state: :normal,
      lines: [content],
      attrs: %{widget: widget}
    )
  end

  def to_view(%Widget{} = widget, _opts) do
    Cell.new(
      id: widget.id,
      kind: :widget,
      state: :normal,
      lines: [inspect(widget.content)],
      attrs: %{widget: widget}
    )
  end

  defp dialog_lines(%Dialog{} = dialog) do
    [dialog.title, ""] ++ String.split(dialog.body, "\n", trim: true)
  end

  defp selected_detail_lines(%Suggest{} = suggest) do
    case Suggest.selected_detail(suggest) do
      nil -> []
      detail -> [""] ++ String.split(detail, "\n", trim: true)
    end
  end
end
