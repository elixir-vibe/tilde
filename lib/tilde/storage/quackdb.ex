defmodule Tilde.Storage.QuackDB do
  @moduledoc "QuackDB-backed implementation of the Tilde storage boundary."

  @behaviour Tilde.Storage

  use QuackDB.Ecto, analytics: false, full_text_search: false, spatial: false

  alias Tilde.Core.Input
  alias Tilde.Session.Summary
  alias Tilde.Storage.EventCodec
  alias Tilde.Storage.Repo
  alias Tilde.Storage.Schema.{Block, SessionState}
  alias Tilde.Storage.Schema.EventRow
  alias Tilde.Storage.Schema.Session, as: StoredSession

  @storage_errors [
    DBConnection.ConnectionError,
    Ecto.ChangeError,
    Ecto.ConstraintError,
    Ecto.InvalidChangesetError,
    Ecto.QueryError,
    ArgumentError,
    RuntimeError
  ]

  @impl true
  def ensure_session(%Tilde.Core.Session{} = session) do
    now = now()
    metadata = stringify_keys(session.metadata)

    Repo.insert_all(
      StoredSession,
      [
        %{
          id: session.id,
          title: Map.get(metadata, "title"),
          metadata: metadata,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict: [set: [updated_at: now, metadata: metadata]],
      conflict_target: [:id]
    )

    :ok
  rescue
    error in @storage_errors -> {:error, error}
  end

  @impl true
  def append_event(%Tilde.Core.Session{} = session, %Tilde.Core.Event{} = event) do
    Repo.transaction(fn ->
      :ok = ensure_session(session)
      event_index = next_event_index(session.id)
      now = now()
      occurred_at = event.at || now

      Repo.insert_all(EventRow, [event_row(session.id, event_index, event, occurred_at, now)])

      blocks = block_rows(session.id, event_index, event, occurred_at)

      if blocks != [] do
        Repo.insert_all(Block, blocks)
      end

      :ok
    end)
    |> case do
      {:ok, :ok} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in @storage_errors -> {:error, error}
  end

  @impl true
  def load_events(session_id) when is_binary(session_id) do
    events =
      Repo.all(
        from(event in EventRow,
          where: event.session_id == ^session_id,
          order_by: [asc: event.event_index],
          select: event.payload
        )
      )

    {:ok, Enum.map(events, &EventCodec.load!/1)}
  rescue
    error in @storage_errors -> {:error, error}
  end

  @impl true
  def load_session(session_id) when is_binary(session_id) do
    with {:ok, events} <- load_events(session_id) do
      session =
        [id: session_id]
        |> Tilde.session()
        |> Tilde.Core.Session.append_events(events)
        |> restore_state(load_state(session_id))

      {:ok, session}
    end
  end

  @impl true
  def save_state(%Tilde.Core.Session{} = session) do
    now = now()
    suggest = Tilde.Core.Session.command_suggestions(session)

    Repo.insert_all(
      SessionState,
      [
        %{
          session_id: session.id,
          input_value: session.input.value,
          input_cursor: session.input.cursor,
          selected_suggestion: if(suggest, do: suggest.selected_index),
          metadata: %{},
          updated_at: now
        }
      ],
      on_conflict: [
        set: [
          input_value: session.input.value,
          input_cursor: session.input.cursor,
          selected_suggestion: if(suggest, do: suggest.selected_index),
          updated_at: now
        ]
      ],
      conflict_target: [:session_id]
    )

    :ok
  rescue
    error in @storage_errors -> {:error, error}
  end

  @impl true
  def session_summaries(_opts \\ []) do
    session_ids =
      Repo.all(from(session in StoredSession, order_by: [asc: session.id], select: session.id))

    texts_by_session =
      Repo.all(
        from(block in Block,
          where: not is_nil(block.text) and block.text != "",
          order_by: [asc: block.session_id, asc: block.event_index, asc: block.block_index],
          select: %{session_id: block.session_id, text: block.text}
        )
      )
      |> Enum.group_by(& &1.session_id, & &1.text)

    summaries =
      Enum.map(session_ids, fn session_id ->
        Summary.from_texts(session_id, Map.get(texts_by_session, session_id, []),
          source: :persisted
        )
      end)

    {:ok, summaries}
  rescue
    error in @storage_errors -> {:error, error}
  end

  @impl true
  def search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 50)

    results =
      Repo.all(
        from(block in Block,
          where: contains_text(block.text, ^query),
          order_by: [desc: block.occurred_at, desc: block.event_index],
          limit: ^limit,
          select: %{
            session_id: block.session_id,
            event_index: block.event_index,
            role: block.role,
            text: block.text,
            occurred_at: block.occurred_at
          }
        )
      )

    {:ok, results}
  rescue
    error in @storage_errors -> {:error, error}
  end

  defp next_event_index(session_id) do
    query = from(event in EventRow, where: event.session_id == ^session_id)
    (Repo.aggregate(query, :max, :event_index) || -1) + 1
  end

  defp event_row(session_id, event_index, %Tilde.Core.Event{} = event, occurred_at, inserted_at) do
    %{
      id: event.id,
      session_id: session_id,
      event_index: event_index,
      event_type: Atom.to_string(event.type),
      payload: EventCodec.dump(event),
      occurred_at: occurred_at,
      inserted_at: inserted_at
    }
  end

  defp block_rows(session_id, event_index, %Tilde.Core.Event{} = event, occurred_at) do
    event
    |> event_texts()
    |> Enum.with_index()
    |> Enum.map(fn {text, block_index} ->
      %{
        id: "#{event.id}:#{block_index}",
        session_id: session_id,
        event_index: event_index,
        block_index: block_index,
        kind: Atom.to_string(event.type),
        role: maybe_to_string(event.role),
        text: text,
        tool_name: event.name,
        metadata: stringify_keys(event.metadata),
        occurred_at: occurred_at
      }
    end)
  end

  defp event_texts(%Tilde.Core.Event{type: :input_changed}), do: []
  defp event_texts(%Tilde.Core.Event{text: text}) when is_binary(text) and text != "", do: [text]

  defp event_texts(%Tilde.Core.Event{chunk: chunk}) when is_binary(chunk) and chunk != "",
    do: [chunk]

  defp event_texts(%Tilde.Core.Event{result: result}) when is_binary(result) and result != "",
    do: [result]

  defp event_texts(_event), do: []

  defp load_state(session_id) do
    Repo.get(SessionState, session_id)
  rescue
    _error in @storage_errors -> nil
  end

  defp restore_state(%Tilde.Core.Session{} = session, %SessionState{} = state) do
    input =
      Input.put_value(session.input, state.input_value || "", cursor: state.input_cursor || 0)

    %{session | input: input}
  end

  defp restore_state(%Tilde.Core.Session{} = session, _state), do: session

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp maybe_to_string(nil), do: nil
  defp maybe_to_string(value), do: to_string(value)

  defp now, do: DateTime.utc_now()
end
