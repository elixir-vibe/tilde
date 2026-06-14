defmodule Tilde.View.Builder do
  @moduledoc """
  Builds shared renderer-neutral view cells from semantic Tilde blocks/widgets.
  """

  alias Tilde.{Block, Choice, Suggest, ToolView, View.Cell, Widget}
  alias Tilde.Template.Source
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

    view
    |> tool_template_cell()
    |> Map.merge(%{
      id: block.id,
      kind: :tool,
      actions: view.actions,
      attrs: %{block: block, view: view, template: :source}
    })
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

  defp tool_template_cell(view) do
    lines = tool_template_lines(view)
    assigns = tool_template_assigns(view, lines)

    {:ok, [cell]} =
      Source.to_cells(
        tool_template_source(lines),
        [assigns: assigns],
        __ENV__
      )

    cell
  end

  defp tool_template_source(lines) do
    body =
      lines
      |> Enum.with_index()
      |> Enum.map_join("\n", fn
        {{:metadata, _value}, index} ->
          ~s|  <.line role="metadata"><.meta>{Enum.at(@lines, #{index})}</.meta></.line>|

        {{:primary, _value}, index} ->
          ~s|  <.line role="primary"><.primary>{Enum.at(@lines, #{index})}</.primary></.line>|

        {{:muted, _value}, index} ->
          ~s|  <.line role="muted"><.muted>{Enum.at(@lines, #{index})}</.muted></.line>|

        {{:hint, _value}, index} ->
          ~s|  <.line role="hint"><.muted>{Enum.at(@lines, #{index})}</.muted></.line>|
      end)

    """
    <.cell kind="tool" state={@state} padding_x={1} padding_y={1}>
      <.tool_call name={@name} segment={@segment} tags={@tags} suffix={@suffix} />
    #{body}
    </.cell>
    """
  end

  defp tool_template_assigns(view, lines) do
    %{
      state: tool_state(view.status),
      name: view.name,
      segment: tool_segment(view.call_segments),
      tags: view.call_tags,
      suffix: view.call_suffix,
      lines: Enum.map(lines, fn {_role, value} -> value end)
    }
  end

  defp tool_template_lines(view) do
    [
      metadata_entry(view.metadata_rows),
      waiting_entry(view),
      stream_entries(view),
      hidden_entry(view)
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp tool_segment([]), do: nil
  defp tool_segment(segments), do: Enum.map_join(segments, " ", &Map.fetch!(&1, :text))

  defp metadata_entry([]), do: nil

  defp metadata_entry(rows),
    do: {:metadata, Enum.map_join(rows, "  ", fn {key, value} -> "#{key} #{value}" end)}

  defp waiting_entry(%{waiting?: true}), do: {:muted, "Waiting…"}
  defp waiting_entry(_view), do: nil

  defp stream_entries(%{streams: [], lines: lines}),
    do: Enum.map(lines, &{:primary, "  #{&1}"})

  defp stream_entries(%{streams: streams}) do
    visible_streams =
      Enum.reject(streams, fn stream -> stream.lines == [] and stream.hidden_lines == 0 end)

    label? = multiple?(streams)

    Enum.flat_map(visible_streams, fn stream ->
      label = if label?, do: [{:muted, stream.kind}], else: []
      visible = Enum.map(stream.lines, &{:primary, "  #{&1}"})

      hidden =
        if stream.hidden_lines > 0,
          do: [{:muted, "  … #{stream.hidden_lines} more #{stream.kind} lines"}],
          else: []

      label ++ visible ++ hidden
    end)
  end

  defp multiple?([_, _ | _]), do: true
  defp multiple?(_streams), do: false

  defp hidden_entry(%{hidden_lines: 0, expanded?: false}), do: nil
  defp hidden_entry(%{hidden_lines: 0, expanded?: true}), do: {:hint, "(ctrl+o to collapse)"}
  defp hidden_entry(view), do: {:hint, "… #{view.hidden_lines} more lines (ctrl+o to expand)"}

  defp choice_lines(choice) do
    [H.line(choice.question, role: :title)] ++
      Enum.map(choice.options, fn option ->
        marker = if option.id in choice.selected, do: "[x]", else: "[ ]"
        description = if Map.get(option, :description), do: " — #{option.description}", else: ""
        H.line("#{marker} #{option.label}#{description}")
      end)
  end
end
