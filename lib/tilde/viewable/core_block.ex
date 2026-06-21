defimpl Tilde.Viewable, for: Tilde.Core.Block do
  alias Tilde.Core.{Block, Choice}
  alias Tilde.Tool.ViewModel
  alias Tilde.View.{Cell, Line, Text}
  alias Tilde.View.Helpers, as: H

  def to_view(block), do: to_view(block, [])

  def to_view(%Block{kind: :message} = block, _opts) do
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

  def to_view(%Block{kind: :tool} = block, _opts) do
    view = ViewModel.view(block)

    view
    |> tool_template_cell()
    |> Map.merge(%{
      id: block.id,
      kind: :tool,
      actions: view.actions,
      attrs: %{block: block, view: view, template: :source}
    })
  end

  def to_view(%Block{kind: :compaction} = block, _opts) do
    Cell.new(
      id: block.id,
      kind: :compaction,
      format: block.format,
      source: block.source,
      actions: block.actions,
      attrs: %{block: block},
      padding_x: 1,
      padding_y: 1
    )
  end

  def to_view(%Block{kind: :choice, choice: %Choice{} = choice} = block, _opts) do
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

  def to_view(%Block{} = block, _opts) do
    Cell.new(id: block.id, kind: block.kind, lines: [inspect(block.kind)])
  end

  defp message_text(%Block{runs: [_ | _] = runs}), do: Enum.map_join(runs, & &1.text)
  defp message_text(%Block{source: source}), do: source

  defp tool_state(status) when status in [:queued, :running, :streaming], do: :pending
  defp tool_state(status) when status in [:success, :done], do: :success
  defp tool_state(:error), do: :error
  defp tool_state(:cancelled), do: :cancelled
  defp tool_state(_status), do: :normal

  defp tool_template_cell(view) do
    Cell.new(
      kind: :tool,
      state: tool_state(view.status),
      lines: [tool_call_line(view) | tool_template_lines(view)],
      padding_x: 1,
      padding_y: 1
    )
  end

  defp tool_call_line(view) do
    parts =
      [Text.new(view.name, :title)] ++
        call_segment_parts(view.call_segments) ++
        tag_parts(view.call_tags) ++ suffix_parts(view.call_suffix)

    Line.new(parts, role: :title)
  end

  defp call_segment_parts(segments) do
    Enum.flat_map(segments, fn segment ->
      prefix = if String.starts_with?(segment.text, ":"), do: "", else: " "
      [Text.new(prefix <> segment.text, segment_style(segment.color))]
    end)
  end

  defp tag_parts([]), do: []
  defp tag_parts(tags), do: [Text.new(" [#{Enum.join(tags, ", ")}]", :muted)]

  defp suffix_parts(nil), do: []
  defp suffix_parts(suffix), do: [Text.new(" (#{suffix})", :muted)]

  defp segment_style(:accent), do: :accent
  defp segment_style(:muted), do: :muted
  defp segment_style(:dim), do: :muted
  defp segment_style(:success), do: :success
  defp segment_style(:error), do: :error
  defp segment_style(:warning), do: :warning
  defp segment_style(_color), do: :plain

  defp tool_template_lines(view) do
    [waiting_entry(view), result_entries(view), stream_entries(view), hidden_entry(view)]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp waiting_entry(%{waiting?: true}), do: line(:muted, "Waiting…")
  defp waiting_entry(_view), do: nil

  defp result_entries(%{entries: []}), do: []

  defp result_entries(%{entries: entries}) do
    entries
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} ->
      separator = if index == 0, do: [], else: []
      body = Enum.map(entry.body, &line(:primary, &1))

      separator ++
        [line(:title, entry.title)] ++
        if(entry.metadata in [nil, ""], do: [], else: [line(:metadata, entry.metadata)]) ++
        body
    end)
  end

  defp stream_entries(%{entries: [_ | _]}), do: []

  defp stream_entries(%{streams: [], lines: lines}),
    do: Enum.map(lines, &output_line/1)

  defp stream_entries(%{streams: streams}) do
    visible_streams =
      Enum.reject(streams, fn stream -> stream.lines == [] and stream.hidden_lines == 0 end)

    label? = multiple?(streams)

    Enum.flat_map(visible_streams, fn stream ->
      label = if label?, do: [line(:muted, stream.kind)], else: []
      visible = Enum.map(stream.lines, &output_line/1)

      label ++ visible
    end)
  end

  defp multiple?([_, _ | _]), do: true
  defp multiple?(_streams), do: false

  defp hidden_entry(%{hidden_lines: 0, expanded?: false}), do: nil

  defp hidden_entry(%{hidden_lines: 0, expanded?: true}),
    do: line(:hint, "(ctrl+o to collapse)")

  defp hidden_entry(view) do
    line(:hint, "… #{view.hidden_lines} #{view.hidden_unit || "more lines"} (ctrl+o to expand)")
  end

  defp output_line("+" <> _rest = text), do: line(:success, "  #{text}")
  defp output_line("-" <> _rest = text), do: line(:error, "  #{text}")
  defp output_line("@@" <> _rest = text), do: line(:muted, "  #{text}")
  defp output_line(text), do: line(:primary, "  #{text}")

  defp line(role, value) do
    Line.new(Text.new(value, line_style(role)), role: role)
  end

  defp line_style(:metadata), do: :muted
  defp line_style(:hint), do: :muted
  defp line_style(role), do: role

  defp choice_lines(choice) do
    [H.line(choice.question, role: :title)] ++
      Enum.map(choice.options, fn option ->
        marker = if option.id in choice.selected, do: "[x]", else: "[ ]"
        description = if Map.get(option, :description), do: " — #{option.description}", else: ""
        H.line("#{marker} #{option.label}#{description}")
      end)
  end
end
