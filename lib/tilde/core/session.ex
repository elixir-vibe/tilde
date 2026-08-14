defmodule Tilde.Core.Session do
  @moduledoc """
  Semantic console session state.

  A session keeps the append-only event log, its reduced transcript, ephemeral
  widgets, status values, and metadata together. The internal log is newest-first
  for constant-time append; use `events/1` when chronological order is required.
  Renderers can subscribe to this state or maintain equivalent assigns in a
  LiveView process.
  """

  alias ReqLLM.StreamChunk

  alias Tilde.Core.{
    AgentRuntime,
    AssistantTurn,
    Block,
    BlockList,
    Event,
    Input,
    Transcript,
    Widget
  }

  @type t :: %__MODULE__{
          id: String.t(),
          event_log: [Event.t()],
          event_count: non_neg_integer(),
          next_event_sequence: non_neg_integer(),
          transcript: Transcript.t(),
          widgets: %{optional(Widget.placement()) => [Widget.t()]},
          statuses: map(),
          assistant: AssistantTurn.t(),
          input: Input.t(),
          metadata: map()
        }

  defstruct id: nil,
            event_log: [],
            event_count: 0,
            next_event_sequence: 0,
            transcript: %Transcript{},
            widgets: %{},
            statuses: %{},
            assistant: %AssistantTurn{},
            input: %Input{},
            metadata: %{}

  @doc "Returns true while the assistant is waiting for first model output."
  @spec assistant_waiting?(t()) :: boolean()
  def assistant_waiting?(%__MODULE__{assistant: assistant}), do: AssistantTurn.waiting?(assistant)

  @doc "Returns true while the assistant turn is active."
  @spec assistant_active?(t()) :: boolean()
  def assistant_active?(%__MODULE__{assistant: assistant}), do: AssistantTurn.active?(assistant)

  @doc "Creates an empty session."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, unique_id()),
      input: Keyword.get(opts, :input, %Input{}),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Returns the event log in chronological order."
  @spec events(t()) :: [Event.t()]
  def events(%__MODULE__{event_log: event_log}), do: Enum.reverse(event_log)

  @doc "Returns events at or after a sequence in chronological order."
  @spec events_since(t(), non_neg_integer()) :: [Event.t()]
  def events_since(%__MODULE__{event_log: event_log}, sequence)
      when is_integer(sequence) and sequence >= 0 do
    event_log
    |> Enum.take_while(&(&1.sequence >= sequence))
    |> Enum.reverse()
  end

  @doc "Returns the latest event, if one exists."
  @spec latest_event(t()) :: Event.t() | nil
  def latest_event(%__MODULE__{event_log: [event | _events]}), do: event
  def latest_event(%__MODULE__{event_log: []}), do: nil

  @doc "Returns whether the session contains no events or resumable state."
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{event_log: [], input: %{value: ""}, metadata: metadata}),
    do: metadata == %{}

  def empty?(%__MODULE__{}), do: false

  @doc "Returns whether an event id exists in the session log."
  @spec event_id?(t(), String.t()) :: boolean()
  def event_id?(%__MODULE__{event_log: event_log}, id) when is_binary(id),
    do: Enum.any?(event_log, &(&1.id == id))

  @doc "Appends an event and updates the derived transcript."
  @spec append_event(t(), Event.t()) :: t()
  def append_event(%__MODULE__{} = session, %Event{} = event) do
    event = sequence_event(event, session.next_event_sequence, :contiguous)
    session = apply_event_without_log(session, event)

    %{
      session
      | event_log: [event | session.event_log],
        event_count: session.event_count + 1,
        next_event_sequence: event.sequence + 1
    }
  end

  @doc "Appends events in order."
  @spec append_events(t(), [Event.t()]) :: t()
  def append_events(%__MODULE__{} = session, []), do: session

  def append_events(%__MODULE__{} = session, events) when is_list(events) do
    {events, next_sequence} =
      Enum.map_reduce(events, session.next_event_sequence, fn event, sequence ->
        event = sequence_event(event, sequence, :ordered)
        {event, event.sequence + 1}
      end)

    updated = Enum.reduce(events, session, &apply_session_event(&2, &1))
    transcript = Transcript.apply_events(events, session.transcript)

    %{
      updated
      | event_log: Enum.reverse(events, session.event_log),
        event_count: session.event_count + length(events),
        next_event_sequence: next_sequence,
        transcript: transcript
    }
  end

  @doc "Adds or replaces a widget by id in its placement."
  @spec put_widget(t(), Widget.t()) :: t()
  def put_widget(%__MODULE__{} = session, %Widget{} = widget) do
    widgets = Map.update(session.widgets, widget.placement, [widget], &replace_widget(&1, widget))
    %{session | widgets: widgets}
  end

  @doc "Removes a widget from all placements."
  @spec delete_widget(t(), String.t()) :: t()
  def delete_widget(%__MODULE__{} = session, id) when is_binary(id) do
    widgets =
      Map.new(session.widgets, fn {placement, items} -> {placement, reject_widget(items, id)} end)

    %{session | widgets: widgets}
  end

  @doc "Returns widgets for a placement."
  @spec widgets(t(), Widget.placement()) :: [Widget.t()]
  def widgets(%__MODULE__{} = session, placement), do: Map.get(session.widgets, placement, [])

  @doc "Replaces the current semantic input state."
  @spec put_input(t(), Input.t()) :: t()
  def put_input(%__MODULE__{} = session, %Input{} = input), do: %{session | input: input}

  @doc "Sets a named status value."
  @spec put_status(t(), String.t(), term()) :: t()
  def put_status(%__MODULE__{} = session, key, value) when is_binary(key) do
    %{session | statuses: Map.put(session.statuses, key, value)}
  end

  @doc "Returns the typed durable agent runtime metadata."
  @spec agent_runtime(t()) :: AgentRuntime.t()
  def agent_runtime(%__MODULE__{metadata: metadata}) do
    metadata
    |> agent_runtime_metadata()
    |> AgentRuntime.load()
  end

  @doc "Stores typed durable agent runtime metadata."
  @spec put_agent_runtime(t(), AgentRuntime.t()) :: t()
  def put_agent_runtime(%__MODULE__{} = session, %AgentRuntime{} = runtime) do
    put_in(session.metadata[:agent_loop], AgentRuntime.dump(runtime))
  end

  @doc "Restores external session metadata into Tilde's canonical metadata shape."
  @spec restore_metadata(t(), map() | nil) :: t()
  def restore_metadata(%__MODULE__{} = session, nil), do: restore_metadata(session, %{})

  def restore_metadata(%__MODULE__{} = session, metadata) when is_map(metadata) do
    metadata =
      metadata
      |> normalize_app_referer_metadata()
      |> Map.delete("agent_loop")
      |> Map.put(
        :agent_loop,
        metadata |> agent_runtime_metadata() |> AgentRuntime.load() |> AgentRuntime.dump()
      )

    %{session | metadata: metadata}
  end

  @doc "Updates a transcript block by id."
  @spec update_block(t(), String.t(), (Block.t() -> Block.t())) :: t()
  def update_block(%__MODULE__{} = session, block_id, fun)
      when is_binary(block_id) and is_function(fun, 1) do
    transcript = %{
      session.transcript
      | blocks: BlockList.update(session.transcript.blocks, block_id, fun)
    }

    %{session | transcript: transcript}
  end

  @doc "Toggles compact/expanded display state for a block."
  @spec toggle_expand(t(), String.t()) :: t()
  def toggle_expand(%__MODULE__{} = session, block_id) when is_binary(block_id) do
    update_block(session, block_id, &Block.toggle_expand/1)
  end

  @doc "Toggles all tool blocks as one semantic expansion group."
  @spec toggle_tool_expansion(t()) :: t()
  def toggle_tool_expansion(%__MODULE__{} = session) do
    tool_blocks = Enum.filter(session.transcript.blocks, &(&1.kind == :tool))
    expand? = Enum.any?(tool_blocks, &(not &1.display.expanded?))

    transcript = %{
      session.transcript
      | blocks:
          Enum.map(session.transcript.blocks, fn
            %Block{kind: :tool} = block -> Block.update_display(block, %{expanded?: expand?})
            %Block{} = block -> block
          end)
    }

    %{session | transcript: transcript}
  end

  @doc "Selects an option in a choice block."
  @spec select_choice(t(), String.t(), String.t()) :: t()
  def select_choice(%__MODULE__{} = session, block_id, option_id)
      when is_binary(block_id) and is_binary(option_id) do
    update_block(session, block_id, &Block.select_choice(&1, option_id))
  end

  defp apply_event_without_log(%__MODULE__{} = session, %Event{} = event) do
    session = apply_session_event(session, event)

    %{session | transcript: Transcript.apply_event(event, session.transcript)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :input_changed} = event) do
    value = event.text || ""

    put_input(session, Input.put_value(session.input, value, cursor: input_cursor(event)))
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :input_submitted}) do
    session
    |> put_input(Input.clear(session.input))
    |> delete_widget("command-suggestions")
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :assistant_turn_started} = event) do
    %{session | assistant: AssistantTurn.waiting(event.block_id)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :assistant_delta} = event) do
    chunk = assistant_delta_chunk(event)
    %{session | assistant: AssistantTurn.apply_chunk(session.assistant, chunk)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :tool_started} = event) do
    chunk = StreamChunk.tool_call(event.name || "tool", event.args || %{}, event.metadata)
    %{session | assistant: AssistantTurn.apply_chunk(session.assistant, chunk)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :assistant_done}) do
    %{session | assistant: AssistantTurn.done(session.assistant)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :assistant_turn_finished}) do
    %{session | assistant: AssistantTurn.done(session.assistant)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :assistant_turn_error} = event) do
    %{session | assistant: AssistantTurn.error(session.assistant, event.result || event.text)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :assistant_turn_cancelled}) do
    %{session | assistant: AssistantTurn.cancelled(session.assistant)}
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :status_changed} = event) do
    update_status(session, event.name || "status", event.status || event.text)
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{}), do: session

  defp assistant_delta_chunk(%Event{text: text, metadata: metadata}) do
    case Map.get(metadata, :chunk_type, Map.get(metadata, "chunk_type", :content)) do
      chunk_type when chunk_type in [:thinking, "thinking"] ->
        StreamChunk.thinking(text || "", metadata)

      _chunk_type ->
        StreamChunk.text(text || "", metadata)
    end
  end

  defp input_cursor(%Event{metadata: %{cursor: cursor}}) when is_integer(cursor), do: cursor
  defp input_cursor(%Event{text: text}) when is_binary(text), do: String.length(text)
  defp input_cursor(_event), do: 0

  defp normalize_app_referer_metadata(%{"app_referer" => app_referer} = metadata) do
    metadata
    |> Map.delete("app_referer")
    |> Map.put_new(:app_referer, app_referer)
  end

  defp normalize_app_referer_metadata(metadata), do: metadata

  defp agent_runtime_metadata(metadata) when is_map(metadata) do
    Map.get(metadata, :agent_loop, Map.get(metadata, "agent_loop"))
  end

  defp update_status(%__MODULE__{} = session, key, nil),
    do: %{session | statuses: Map.delete(session.statuses, key)}

  defp update_status(%__MODULE__{} = session, key, value),
    do: %{session | statuses: Map.put(session.statuses, key, value)}

  defp sequence_event(%Event{sequence: nil} = event, sequence, _mode),
    do: %{event | sequence: sequence}

  defp sequence_event(%Event{sequence: sequence} = event, sequence, _mode), do: event

  defp sequence_event(%Event{sequence: actual} = event, expected, :ordered)
       when is_integer(actual) and actual > expected,
       do: event

  defp sequence_event(%Event{sequence: actual}, expected, _mode) do
    raise ArgumentError,
          "event sequence #{inspect(actual)} does not follow session sequence #{expected}"
  end

  defp replace_widget(widgets, %Widget{id: id} = widget) do
    [widget | reject_widget(widgets, id)]
  end

  defp reject_widget(widgets, id), do: Enum.reject(widgets, &(&1.id == id))

  defp unique_id, do: "session_#{System.unique_integer([:positive, :monotonic])}"
end
