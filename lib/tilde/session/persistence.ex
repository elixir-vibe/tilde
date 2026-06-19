defmodule Tilde.Session.Persistence do
  @moduledoc "Persistence boundary for session state and events."

  require Logger

  alias Tilde.Core.{Event, Session}
  alias Tilde.Storage

  @spec persist_if_changed(Session.t(), Session.t()) :: :ok
  def persist_if_changed(%Session{} = previous, %Session{} = current) do
    if previous != current do
      persist(previous, current)
    end

    :ok
  end

  @spec persist(Session.t(), Session.t()) :: :ok
  def persist(%Session{} = previous, %Session{} = current) do
    previous_ids = MapSet.new(previous.events, & &1.id)

    current.events
    |> Enum.reject(&MapSet.member?(previous_ids, &1.id))
    |> Enum.each(&persist_event(current, &1))

    persist_state(current)
  end

  defp persist_event(%Session{} = session, %Event{} = event) do
    case Storage.append_event(session, event) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to persist Tilde session event: #{inspect(reason)}")
    end
  end

  defp persist_state(%Session{} = session) do
    case Storage.save_state(session) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("failed to persist Tilde session state: #{inspect(reason)}")
    end
  end
end
