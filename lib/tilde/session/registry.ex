defmodule Tilde.Session.Registry do
  @moduledoc """
  Registry helpers for named Tilde session servers.

  The standalone demo uses this to support isolated LiveView sessions without
  creating dynamic atoms for untrusted session ids.
  """

  @doc "Ensures the local session registry is running."
  @spec ensure_started() :: {:ok, pid()} | {:error, term()}
  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil -> start_unlinked()
      pid -> {:ok, pid}
    end
  end

  defp start_unlinked do
    case Registry.start_link(keys: :unique, name: __MODULE__) do
      {:ok, pid} ->
        Process.unlink(pid)
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Returns current named sessions registered in the local registry."
  @spec sessions() :: [Tilde.Core.Session.t()]
  def sessions do
    case ensure_started() do
      {:ok, _pid} ->
        __MODULE__
        |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
        |> Enum.flat_map(fn {_id, pid} ->
          session_for_pid(pid)
        end)
        |> Enum.sort_by(& &1.id)

      _error ->
        []
    end
  end

  defp session_for_pid(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      [Tilde.Session.Server.get_session(pid)]
    else
      []
    end
  catch
    :exit, _reason -> []
  end

  @doc "Returns a safe Registry via tuple for a session id."
  @spec via(String.t()) :: GenServer.name()
  def via(session_id) when is_binary(session_id) do
    {:via, Registry, {__MODULE__, normalize_id(session_id)}}
  end

  @doc "Normalizes a user-provided session id for registry/session use."
  @spec normalize_id(String.t() | nil) :: String.t()
  def normalize_id(nil), do: "shared"

  def normalize_id(id) when is_binary(id) do
    id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 48)
    |> case do
      "" -> "shared"
      normalized -> normalized
    end
  end
end
