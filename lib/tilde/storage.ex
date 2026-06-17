defmodule Tilde.Storage do
  @moduledoc "Storage boundary for durable Tilde sessions."

  alias Tilde.Core.{Event, Session}
  alias Tilde.Storage.EventPolicy

  @type search_result :: %{
          session_id: String.t(),
          event_index: non_neg_integer(),
          role: String.t() | nil,
          text: String.t(),
          occurred_at: DateTime.t() | NaiveDateTime.t() | nil
        }

  @callback ensure_session(Session.t()) :: :ok | {:error, term()}
  @callback append_event(Session.t(), Event.t()) :: :ok | {:error, term()}
  @callback load_events(String.t()) :: {:ok, [Event.t()]} | {:error, term()}
  @callback load_session(String.t()) :: {:ok, Session.t()} | {:error, term()}
  @callback save_state(Session.t()) :: :ok | {:error, term()}
  @callback search(String.t(), keyword()) :: {:ok, [search_result()]} | {:error, term()}

  @doc "Returns the configured storage adapter, if any."
  @spec adapter() :: module() | nil
  def adapter, do: Application.get_env(:tilde, :storage_adapter)

  @doc "Ensures session metadata exists in durable storage."
  @spec ensure_session(Session.t()) :: :ok | {:error, term()}
  def ensure_session(%Session{} = session), do: dispatch(:ensure_session, [session])

  @doc "Appends one canonical session event to durable storage."
  @spec append_event(Session.t(), Event.t()) :: :ok | {:error, term()}
  def append_event(%Session{} = session, %Event{} = event) do
    if EventPolicy.persist?(event) do
      dispatch(:append_event, [session, event])
    else
      :ok
    end
  end

  @doc "Loads canonical events for a session id in replay order."
  @spec load_events(String.t()) :: {:ok, [Event.t()]} | {:error, term()}
  def load_events(session_id) when is_binary(session_id),
    do: dispatch(:load_events, [session_id], {:ok, []})

  @doc "Loads a session by replaying stored canonical events."
  @spec load_session(String.t()) :: {:ok, Session.t()} | {:error, term()}
  def load_session(session_id) when is_binary(session_id) do
    dispatch(:load_session, [session_id], {:ok, Tilde.session(id: session_id)})
  end

  @doc "Saves resumable draft state for a session."
  @spec save_state(Session.t()) :: :ok | {:error, term()}
  def save_state(%Session{} = session), do: dispatch(:save_state, [session])

  @doc "Searches durable session text projections."
  @spec search(String.t(), keyword()) :: {:ok, [search_result()]} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query),
    do: dispatch(:search, [query, opts], {:ok, []})

  defp dispatch(function, args, fallback \\ :ok) do
    case adapter() do
      nil -> fallback
      module -> apply(module, function, args)
    end
  end
end
