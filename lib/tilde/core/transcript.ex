defmodule Tilde.Core.Transcript do
  @moduledoc """
  Reducer from append-only events to semantic transcript blocks.
  """

  alias Tilde.Core.{Block, BlockList, Event}

  @type t :: %__MODULE__{
          blocks: [Block.t()],
          statuses: map(),
          metadata: map()
        }

  defstruct blocks: [], statuses: %{}, metadata: %{}

  @doc "Builds a transcript by applying events in order."
  @spec from_events([Event.t()]) :: t()
  def from_events(events) when is_list(events), do: apply_events(events, new())

  @doc "Applies events in order."
  @spec apply_events([Event.t()], t()) :: t()
  def apply_events([], %__MODULE__{} = transcript), do: transcript

  def apply_events(events, %__MODULE__{blocks: []} = transcript) when is_list(events) do
    events
    |> Enum.reduce(transcript, &apply_event_reversed/2)
    |> then(fn %__MODULE__{blocks: blocks} = transcript ->
      %{transcript | blocks: Enum.reverse(blocks)}
    end)
  end

  def apply_events(events, %__MODULE__{} = transcript) when is_list(events) do
    Enum.reduce(events, transcript, &apply_event/2)
  end

  @doc "Creates an empty transcript."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Applies one event."
  @spec apply_event(Event.t(), t()) :: t()
  def apply_event(%Event{type: :user_message} = event, %__MODULE__{} = transcript) do
    append_block(transcript, Block.message(block_id(event), :user, event.text || ""))
  end

  def apply_event(%Event{type: :assistant_delta} = event, %__MODULE__{} = transcript) do
    append_or_update_assistant(transcript, event)
  end

  def apply_event(%Event{type: :input_changed}, %__MODULE__{} = transcript), do: transcript

  def apply_event(%Event{type: :input_submitted} = event, %__MODULE__{} = transcript) do
    append_block(transcript, Block.message(block_id(event), :user, event.text || ""))
  end

  def apply_event(%Event{type: :assistant_done} = event, %__MODULE__{} = transcript) do
    block = Block.message(block_id(event), :assistant, event.text || "")
    append_block(transcript, block)
  end

  def apply_event(%Event{type: :tool_started} = event, %__MODULE__{} = transcript) do
    id = event.tool_call_id || block_id(event)
    block = Block.tool(id, event.name || "tool", event.args, metadata: event.metadata)
    append_block(transcript, block)
  end

  def apply_event(%Event{type: :tool_stream} = event, %__MODULE__{} = transcript) do
    update_block(transcript, event.tool_call_id || event.block_id, fn block ->
      Block.append_stream(block, event.stream || :stdout, event.chunk || "")
    end)
  end

  def apply_event(%Event{type: :tool_done} = event, %__MODULE__{} = transcript) do
    update_block(transcript, event.tool_call_id || event.block_id, fn block ->
      Block.finish_tool(block, event.status || :success, event.result)
    end)
  end

  def apply_event(%Event{type: :block_display_changed} = event, %__MODULE__{} = transcript) do
    update_block(transcript, event.block_id || event.tool_call_id, fn block ->
      Block.update_display(block, event.display)
    end)
  end

  def apply_event(%Event{type: type}, %__MODULE__{} = transcript)
      when type in [
             :assistant_turn_started,
             :assistant_turn_finished,
             :assistant_turn_error,
             :assistant_turn_cancelled
           ],
      do: transcript

  def apply_event(%Event{type: :context_compacted} = event, %__MODULE__{} = transcript) do
    append_block(
      transcript,
      Block.compaction(block_id(event), event.text || "",
        metadata: Map.put(event.metadata, :type, :context_compaction)
      )
    )
  end

  def apply_event(%Event{type: :status_changed} = event, %__MODULE__{} = transcript) do
    key = event.name || "status"
    value = event.status || event.text

    statuses =
      if is_nil(value),
        do: Map.delete(transcript.statuses, key),
        else: Map.put(transcript.statuses, key, value)

    %{transcript | statuses: statuses}
  end

  defp apply_event_reversed(%Event{type: :user_message} = event, %__MODULE__{} = transcript) do
    prepend_block(transcript, Block.message(block_id(event), :user, event.text || ""))
  end

  defp apply_event_reversed(%Event{type: :assistant_delta} = event, %__MODULE__{} = transcript) do
    append_or_update_assistant_reversed(transcript, event)
  end

  defp apply_event_reversed(%Event{type: :input_changed}, %__MODULE__{} = transcript),
    do: transcript

  defp apply_event_reversed(%Event{type: :input_submitted} = event, %__MODULE__{} = transcript) do
    prepend_block(transcript, Block.message(block_id(event), :user, event.text || ""))
  end

  defp apply_event_reversed(%Event{type: :assistant_done} = event, %__MODULE__{} = transcript) do
    prepend_block(transcript, Block.message(block_id(event), :assistant, event.text || ""))
  end

  defp apply_event_reversed(%Event{type: :tool_started} = event, %__MODULE__{} = transcript) do
    id = event.tool_call_id || block_id(event)
    block = Block.tool(id, event.name || "tool", event.args, metadata: event.metadata)
    prepend_block(transcript, block)
  end

  defp apply_event_reversed(%Event{type: :tool_stream} = event, %__MODULE__{} = transcript) do
    update_block(transcript, event.tool_call_id || event.block_id, fn block ->
      Block.append_stream(block, event.stream || :stdout, event.chunk || "")
    end)
  end

  defp apply_event_reversed(%Event{type: :tool_done} = event, %__MODULE__{} = transcript) do
    update_block(transcript, event.tool_call_id || event.block_id, fn block ->
      Block.finish_tool(block, event.status || :success, event.result)
    end)
  end

  defp apply_event_reversed(
         %Event{type: :block_display_changed} = event,
         %__MODULE__{} = transcript
       ) do
    update_block(transcript, event.block_id || event.tool_call_id, fn block ->
      Block.update_display(block, event.display)
    end)
  end

  defp apply_event_reversed(%Event{type: type}, %__MODULE__{} = transcript)
       when type in [
              :assistant_turn_started,
              :assistant_turn_finished,
              :assistant_turn_error,
              :assistant_turn_cancelled
            ],
       do: transcript

  defp apply_event_reversed(%Event{type: :context_compacted} = event, %__MODULE__{} = transcript) do
    prepend_block(
      transcript,
      Block.compaction(block_id(event), event.text || "",
        metadata: Map.put(event.metadata, :type, :context_compaction)
      )
    )
  end

  defp apply_event_reversed(%Event{type: :status_changed} = event, %__MODULE__{} = transcript) do
    key = event.name || "status"
    value = event.status || event.text

    statuses =
      if is_nil(value),
        do: Map.delete(transcript.statuses, key),
        else: Map.put(transcript.statuses, key, value)

    %{transcript | statuses: statuses}
  end

  defp append_or_update_assistant(%__MODULE__{} = transcript, %Event{} = event) do
    root_id = event.block_id || last_assistant_id(transcript) || block_id(event)
    id = assistant_target_id(transcript, root_id)
    text = event.text || ""

    cond do
      thinking_delta?(event) and has_block?(transcript, id) ->
        update_block(transcript, id, &Block.append_thinking(&1, text))

      thinking_delta?(event) ->
        append_block(
          transcript,
          Block.message(id, :assistant, "",
            metadata: assistant_metadata(id, root_id, %{thinking: text})
          )
        )

      has_block?(transcript, id) ->
        update_block(transcript, id, &Block.append_text(&1, text))

      true ->
        append_block(
          transcript,
          Block.message(id, :assistant, text, metadata: assistant_metadata(id, root_id))
        )
    end
  end

  defp append_or_update_assistant_reversed(%__MODULE__{} = transcript, %Event{} = event) do
    root_id = event.block_id || last_assistant_id_reversed(transcript) || block_id(event)
    id = assistant_target_id_reversed(transcript, root_id)
    text = event.text || ""

    cond do
      thinking_delta?(event) and has_block?(transcript, id) ->
        update_block(transcript, id, &Block.append_thinking(&1, text))

      thinking_delta?(event) ->
        prepend_block(
          transcript,
          Block.message(id, :assistant, "",
            metadata: assistant_metadata(id, root_id, %{thinking: text})
          )
        )

      has_block?(transcript, id) ->
        update_block(transcript, id, &Block.append_text(&1, text))

      true ->
        prepend_block(
          transcript,
          Block.message(id, :assistant, text, metadata: assistant_metadata(id, root_id))
        )
    end
  end

  defp thinking_delta?(%Event{metadata: metadata}) do
    Map.get(metadata, :chunk_type, Map.get(metadata, "chunk_type")) in [:thinking, "thinking"]
  end

  defp assistant_target_id_reversed(%__MODULE__{blocks: blocks} = transcript, root_id) do
    case blocks do
      [%Block{kind: :message, role: :assistant, id: id, metadata: metadata} | _rest] ->
        if id == root_id or Map.get(metadata, :root_block_id) == root_id do
          id
        else
          next_assistant_id(transcript, root_id)
        end

      _blocks ->
        next_assistant_id(transcript, root_id)
    end
  end

  defp assistant_target_id(%__MODULE__{} = transcript, root_id) do
    case List.last(transcript.blocks) do
      %Block{kind: :message, role: :assistant, id: id, metadata: metadata} ->
        if id == root_id or Map.get(metadata, :root_block_id) == root_id do
          id
        else
          next_assistant_id(transcript, root_id)
        end

      _block ->
        next_assistant_id(transcript, root_id)
    end
  end

  defp next_assistant_id(%__MODULE__{} = transcript, root_id) do
    if has_block?(transcript, root_id),
      do: "#{root_id}:#{assistant_continuation_count(transcript, root_id) + 1}",
      else: root_id
  end

  defp assistant_continuation_count(%__MODULE__{} = transcript, root_id) do
    Enum.count(transcript.blocks, fn
      %Block{kind: :message, role: :assistant, metadata: %{root_block_id: ^root_id}} -> true
      _block -> false
    end)
  end

  defp assistant_metadata(id, root_id, metadata \\ %{})
  defp assistant_metadata(root_id, root_id, metadata), do: metadata
  defp assistant_metadata(_id, root_id, metadata), do: Map.put(metadata, :root_block_id, root_id)

  defp append_block(%__MODULE__{} = transcript, %Block{} = block) do
    %{transcript | blocks: transcript.blocks ++ [block]}
  end

  defp prepend_block(%__MODULE__{} = transcript, %Block{} = block) do
    %{transcript | blocks: [block | transcript.blocks]}
  end

  defp update_block(%__MODULE__{} = transcript, id, fun) when is_function(fun, 1) do
    %{transcript | blocks: BlockList.update(transcript.blocks, id, fun)}
  end

  defp has_block?(%__MODULE__{} = transcript, id) do
    Enum.any?(transcript.blocks, &(&1.id == id))
  end

  defp last_assistant_id_reversed(%__MODULE__{} = transcript) do
    Enum.find_value(transcript.blocks, fn
      %Block{kind: :message, role: :assistant, id: id} -> id
      _block -> nil
    end)
  end

  defp last_assistant_id(%__MODULE__{} = transcript) do
    transcript.blocks
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Block{kind: :message, role: :assistant, id: id} -> id
      _block -> nil
    end)
  end

  defp block_id(%Event{block_id: id}) when is_binary(id), do: id
  defp block_id(%Event{id: id}), do: String.replace_prefix(id, "evt_", "blk_")
end
