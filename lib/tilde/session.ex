defmodule Tilde.Session do
  @moduledoc """
  Semantic console session state.

  A session keeps the append-only event log, its reduced transcript, ephemeral
  widgets, status values, and metadata together. Renderers can subscribe to this
  state or maintain equivalent assigns in a LiveView process.
  """

  alias Tilde.{Block, BlockList, Event, Input, Transcript, Widget}

  @type t :: %__MODULE__{
          id: String.t(),
          events: [Event.t()],
          transcript: Transcript.t(),
          widgets: %{optional(Widget.placement()) => [Widget.t()]},
          statuses: map(),
          input: Input.t(),
          metadata: map()
        }

  defstruct id: nil,
            events: [],
            transcript: %Transcript{},
            widgets: %{},
            statuses: %{},
            input: %Input{},
            metadata: %{}

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

  @doc "Keeps only the newest events and rebuilds derived transcript/status state."
  @spec trim_events(t(), pos_integer() | nil | false) :: t()
  def trim_events(%__MODULE__{} = session, limit)
      when limit in [nil, false] or (is_integer(limit) and limit > 0) do
    case limit do
      value when is_integer(value) and length(session.events) > value ->
        events = Enum.take(session.events, -value)

        replay =
          append_events(%{session | events: [], transcript: %Transcript{}, statuses: %{}}, events)

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

  @doc "Selects an option in a choice block."
  @spec select_choice(t(), String.t(), String.t()) :: t()
  def select_choice(%__MODULE__{} = session, block_id, option_id)
      when is_binary(block_id) and is_binary(option_id) do
    update_block(session, block_id, &Block.select_choice(&1, option_id))
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

  defp apply_session_event(%__MODULE__{} = session, %Event{type: :status_changed} = event) do
    update_status(session, event.name || "status", event.status || event.text)
  end

  defp apply_session_event(%__MODULE__{} = session, %Event{}), do: session

  defp input_cursor(%Event{metadata: %{cursor: cursor}}) when is_integer(cursor), do: cursor
  defp input_cursor(%Event{text: text}) when is_binary(text), do: String.length(text)
  defp input_cursor(_event), do: 0

  defp update_status(%__MODULE__{} = session, key, nil),
    do: %{session | statuses: Map.delete(session.statuses, key)}

  defp update_status(%__MODULE__{} = session, key, value),
    do: %{session | statuses: Map.put(session.statuses, key, value)}

  defp put_command_suggestions(%__MODULE__{} = session, value) do
    case Tilde.Command.suggestions(value) do
      nil -> delete_widget(session, "command-suggestions")
      suggest -> put_widget(session, Widget.new("command-suggestions", :above_input, suggest))
    end
  end

  defp replace_widget(widgets, %Widget{id: id} = widget) do
    [widget | reject_widget(widgets, id)]
  end

  defp reject_widget(widgets, id), do: Enum.reject(widgets, &(&1.id == id))

  defp unique_id, do: "session_#{System.unique_integer([:positive, :monotonic])}"
end
