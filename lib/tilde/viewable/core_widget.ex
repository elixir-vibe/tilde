defimpl Tilde.Viewable, for: Tilde.Core.Widget do
  alias Tilde.Core.{Suggest, Widget}
  alias Tilde.View.Cell

  def to_view(widget), do: to_view(widget, [])

  def to_view(%Widget{content: %Suggest{} = suggest} = widget, _opts) do
    lines =
      [suggest.title] ++
        Enum.map(suggest.items, fn item ->
          item.label <>
            String.duplicate(" ", max(1, 12 - String.length(item.label))) <> item.description
        end)

    Cell.new(
      id: widget.id,
      kind: :suggest,
      state: :normal,
      lines: lines,
      attrs: %{widget: widget, suggest: suggest}
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
end
