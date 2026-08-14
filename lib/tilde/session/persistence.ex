defmodule Tilde.Session.Persistence do
  @moduledoc "Persistence boundary for session state and events."

  alias Tilde.Core.{Event, Session}
  alias Tilde.Storage
  alias Tilde.Storage.Error

  @spec persist_if_changed(Session.t(), Session.t()) :: :ok
  def persist_if_changed(%Session{} = previous, %Session{} = current) do
    if previous != current do
      persist(previous, current)
    end

    :ok
  end

  @spec persist(Session.t(), Session.t()) :: :ok
  def persist(%Session{} = previous, %Session{} = current) do
    write!(:ensure_session, fn -> Storage.ensure_session(current) end)

    current
    |> Session.events_since(previous.next_event_sequence)
    |> Enum.each(&persist_event(current, &1))

    persist_state(current)
  end

  defp persist_event(%Session{} = session, %Event{} = event) do
    write!(:append_event, fn -> Storage.append_event(session, event) end)
  end

  defp persist_state(%Session{} = session) do
    write!(:save_state, fn -> Storage.save_state(session) end)
  end

  defp write!(operation, fun) do
    case fun.() do
      :ok -> :ok
      {:error, reason} -> raise Error, operation: operation, reason: reason
    end
  end
end
