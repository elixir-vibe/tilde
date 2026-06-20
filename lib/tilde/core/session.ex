defmodule Tilde.Core.Session do
  @moduledoc """
  Semantic console session state.

  A session keeps the append-only event log, its reduced transcript, ephemeral
  widgets, status values, and metadata together. Renderers can subscribe to this
  state or maintain equivalent assigns in a LiveView process.
  """

  alias ReqLLM.StreamChunk

  alias Tilde.Core.{
    AgentRuntime,
    AssistantTurn,
    Block,
    BlockList,
    Event,
    Input,
    Suggest,
    Transcript,
    Widget
  }

  @type t :: %__MODULE__{
          id: String.t(),
          events: [Event.t()],
          transcript: Transcript.t(),
          widgets: %{optional(Widget.placement()) => [Widget.t()]},
          statuses: map(),
          assistant: AssistantTurn.t(),
          input: Input.t(),
          metadata: map()
        }

  defstruct id: nil,
            events: [],
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

  @doc "Appends an event and updates the derived transcript."
  @spec append_event(t(), Event.t()) :: t()
  def append_event(%__MODULE__{} = session, %Event{} = event) do
    events = session.events ++ [event]

    session = apply_session_event(session, event)

    %{
      session
      | events: events,
        transcript: Transcript.apply_event(event, session.transcript)
    }
  end

  @doc "Appends events in order."
  @spec append_events(t(), [Event.t()]) :: t()
  def append_events(%__MODULE__{} = session, events) when is_list(events) do
    Enum.reduce(events, session, &append_event(&2, &1))
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
      |> Map.delete("agent_loop")
      |> Map.put(
        :agent_loop,
        metadata |> agent_runtime_metadata() |> AgentRuntime.load() |> AgentRuntime.dump()
      )

    %{session | metadata: metadata}
  end

  @doc "Keeps only the newest events and rebuilds derived transcript/status state."
  @spec trim_events(t(), pos_integer() | nil | false) :: t()
  def trim_events(%__MODULE__{} = session, limit)
      when limit in [nil, false] or (is_integer(limit) and limit > 0) do
    case limit do
      value when is_integer(value) and length(session.events) > value ->
        events = Enum.take(session.events, -value)

        replay =
          append_events(
            %{
              session
              | events: [],
                transcript: %Transcript{},
                statuses: %{},
                assistant: %AssistantTurn{}
            },
            events
          )

        %{replay | input: session.input, widgets: session.widgets, metadata: session.metadata}

      _other ->
        session
    end
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

  @doc "Returns the active command suggestion widget content."
  @spec command_suggestions(t()) :: Suggest.t() | nil
  def command_suggestions(%__MODULE__{} = session) do
    session
    |> widgets(:above_input)
    |> Enum.find_value(fn
      %Widget{id: "command-suggestions", content: %Suggest{} = suggest} -> suggest
      _widget -> nil
    end)
  end

  @doc "Moves the active command suggestion selection forward."
  @spec select_next_suggestion(t()) :: t()
  def select_next_suggestion(%__MODULE__{} = session) do
    update_command_suggestions(session, &Suggest.next/1)
  end

  @doc "Moves the active command suggestion selection backward."
  @spec select_previous_suggestion(t()) :: t()
  def select_previous_suggestion(%__MODULE__{} = session) do
    update_command_suggestions(session, &Suggest.previous/1)
  end

  @doc "Clears active command suggestions."
  @spec cancel_suggestions(t()) :: t()
  def cancel_suggestions(%__MODULE__{} = session),
    do: delete_widget(session, "command-suggestions")

  @doc "Accepts the selected command suggestion into the input draft."
  @spec accept_suggestion(t()) :: {:ok, t()} | :error
  def accept_suggestion(%__MODULE__{} = session) do
    case selected_suggestion_completion(session) do
      nil -> :error
      completion -> {:ok, change_input(session, Input.put_value(session.input, completion))}
    end
  end

  @doc "Submits the selected command suggestion, or completes it when it needs arguments."
  @spec submit_suggestion(t()) :: {:ok, t()} | :error
  def submit_suggestion(%__MODULE__{} = session) do
    case selected_suggestion_completion(session) do
      nil ->
        :error

      completion ->
        if String.ends_with?(completion, " ") do
          {:ok, change_input(session, Input.put_value(session.input, completion))}
        else
          {:ok, append_event(session, Tilde.input_submitted(completion))}
        end
    end
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :input_changed} = event) do
    value = event.text || ""

    session
    |> put_input(Input.put_value(session.input, value, cursor: input_cursor(event)))
    |> put_command_suggestions(value)
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

  defp agent_runtime_metadata(metadata) when is_map(metadata) do
    Map.get(metadata, :agent_loop, Map.get(metadata, "agent_loop"))
  end

  defp update_status(%__MODULE__{} = session, key, nil),
    do: %{session | statuses: Map.delete(session.statuses, key)}

  defp update_status(%__MODULE__{} = session, key, value),
    do: %{session | statuses: Map.put(session.statuses, key, value)}

  defp selected_suggestion_completion(%__MODULE__{} = session) do
    case command_suggestions(session) do
      %Suggest{} = suggest -> Tilde.Command.completion(suggest)
      nil -> nil
    end
  end

  defp put_command_suggestions(%__MODULE__{} = session, value) do
    previous_id = command_suggestions(session) && command_suggestions(session).selected_id

    case Tilde.Command.suggestions(value) do
      nil ->
        delete_widget(session, "command-suggestions")

      suggest ->
        put_widget(
          session,
          Widget.new("command-suggestions", :above_input, Suggest.select_id(suggest, previous_id))
        )
    end
  end

  defp update_command_suggestions(%__MODULE__{} = session, fun) when is_function(fun, 1) do
    case command_suggestions(session) do
      %Suggest{} = suggest ->
        put_widget(session, Widget.new("command-suggestions", :above_input, fun.(suggest)))

      nil ->
        session
    end
  end

  defp change_input(%__MODULE__{} = session, %Input{} = input) do
    event = Tilde.input_changed(input.value, metadata: %{cursor: input.cursor})
    append_event(session, event)
  end

  defp replace_widget(widgets, %Widget{id: id} = widget) do
    [widget | reject_widget(widgets, id)]
  end

  defp reject_widget(widgets, id), do: Enum.reject(widgets, &(&1.id == id))

  defp unique_id, do: "session_#{System.unique_integer([:positive, :monotonic])}"
end
