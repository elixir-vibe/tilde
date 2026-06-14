defmodule Tilde.View.Builder do
  @moduledoc """
  Builds shared renderer-neutral view cells from semantic Tilde blocks/widgets.
  """

  alias Tilde.{Block, Choice, Suggest, ToolView, View.Cell, Widget}
  alias Tilde.View.Helpers, as: H

  @doc "Builds a view cell from a transcript block."
  @spec block(Block.t()) :: Cell.t()
  def block(%Block{kind: :message} = block) do
    Cell.new(
      id: block.id,
      kind: :message,
      role: block.role,
      format: block.format,
      source: message_text(block),
      runs: block.runs,
      padding_x: 0,
      padding_y: 0
    )
  end

  def block(%Block{kind: :tool} = block) do
    view = ToolView.view(block)

    Cell.new(
      id: block.id,
      kind: :tool,
      state: tool_state(view.status),
      lines: tool_lines(view),
      actions: view.actions,
      attrs: %{block: block, view: view},
      padding_x: 1,
      padding_y: 1
    )
  end

  def block(%Block{kind: :choice, choice: %Choice{} = choice} = block) do
    Cell.new(
      id: block.id,
      kind: :choice,
      state: :normal,
      lines: choice_lines(choice),
      actions: choice.actions,
      attrs: %{block: block, choice: choice},
      padding_x: 1,
      padding_y: 1
    )
  end

  def block(%Block{} = block) do
    Cell.new(id: block.id, kind: block.kind, lines: [inspect(block.kind)])
  end

  @doc "Builds a view cell from a widget."
  @spec widget(Widget.t()) :: Cell.t()
  def widget(%Widget{content: %Suggest{} = suggest} = widget) do
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

  def widget(%Widget{} = widget) do
    Cell.new(
      id: widget.id,
      kind: :widget,
      state: :normal,
      lines: [inspect(widget.content)],
      attrs: %{widget: widget}
    )
  end

  defp message_text(%Block{runs: [_ | _] = runs}), do: Enum.map_join(runs, & &1.text)
  defp message_text(%Block{source: source}), do: source

  defp tool_state(status) when status in [:queued, :running, :streaming], do: :pending
  defp tool_state(status) when status in [:success, :done], do: :success
  defp tool_state(:error), do: :error
  defp tool_state(:cancelled), do: :cancelled
  defp tool_state(_status), do: :normal

  defp tool_lines(view) do
    [
      tool_call_line(view),
      metadata_line(view.metadata_rows),
      waiting_line(view),
      stream_lines(view),
      hidden_line(view)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp tool_call_line(view) do
    H.tool_call(view.name,
      segments: view.call_segments,
      tags: view.call_tags,
      suffix: view.call_suffix
    )
  end

  defp metadata_line([]), do: nil

  defp metadata_line(rows),
    do: rows |> Enum.map_join("  ", fn {key, value} -> "#{key} #{value}" end) |> H.metadata()

  defp waiting_line(%{waiting?: true}), do: H.muted("Waiting…")
  defp waiting_line(_view), do: nil

  defp stream_lines(%{streams: [], lines: lines}),
    do: Enum.map(lines, &("  #{&1}" |> H.primary()))

  defp stream_lines(%{streams: streams}) do
    visible_streams =
      Enum.reject(streams, fn stream -> stream.lines == [] and stream.hidden_lines == 0 end)

    label? = multiple?(streams)

    Enum.flat_map(visible_streams, fn stream ->
      label = if label?, do: [H.muted(stream.kind)], else: []
      visible = Enum.map(stream.lines, &("  #{&1}" |> H.primary()))

      hidden =
        if stream.hidden_lines > 0,
          do: [H.muted("  … #{stream.hidden_lines} more #{stream.kind} lines")],
          else: []

      label ++ visible ++ hidden
    end)
  end

  defp multiple?([_, _ | _]), do: true
  defp multiple?(_streams), do: false

  defp hidden_line(%{hidden_lines: 0, expanded?: false}), do: nil
  defp hidden_line(%{hidden_lines: 0, expanded?: true}), do: H.collapse_hint()
  defp hidden_line(view), do: H.hint("… #{view.hidden_lines} more lines (ctrl+o to expand)")

  defp choice_lines(choice) do
    [H.line(choice.question, role: :title)] ++
      Enum.map(choice.options, fn option ->
        marker = if option.id in choice.selected, do: "[x]", else: "[ ]"
        description = if Map.get(option, :description), do: " — #{option.description}", else: ""
        H.line("#{marker} #{option.label}#{description}")
      end)
  end
end
