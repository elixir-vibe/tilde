defmodule Tilde.Session.Supervisor do
  @moduledoc "Supervises the registry, session servers, and session-owned agent tasks."

  use Supervisor

  @doc "Starts the session infrastructure."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Tilde.Session.Registry},
      {Task.Supervisor, name: Tilde.Session.TaskSupervisor},
      {DynamicSupervisor, name: Tilde.Session.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end

  @doc "Ensures the Tilde application and its session infrastructure are running."
  @spec ensure_started() :: {:ok, pid()} | {:error, term()}
  def ensure_started do
    with {:ok, _apps} <- Application.ensure_all_started(:tilde),
         pid when is_pid(pid) <- Process.whereis(__MODULE__) do
      {:ok, pid}
    else
      nil -> {:error, :session_supervisor_not_started}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stops every dynamically supervised session server."
  @spec stop_sessions() :: :ok
  def stop_sessions do
    case Process.whereis(Tilde.Session.DynamicSupervisor) do
      pid when is_pid(pid) ->
        pid
        |> DynamicSupervisor.which_children()
        |> Enum.each(fn {_, child, _, _} ->
          DynamicSupervisor.terminate_child(Tilde.Session.DynamicSupervisor, child)
        end)

      nil ->
        :ok
    end

    :ok
  end
end
