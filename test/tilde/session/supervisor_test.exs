defmodule Tilde.Session.SupervisorTest do
  use TildeTest.Case

  alias Tilde.Session.{Registry, Server}

  test "session infrastructure is application supervised" do
    assert is_pid(Process.whereis(Tilde.Session.Supervisor))
    assert is_pid(Process.whereis(Registry))
    assert is_pid(Process.whereis(Tilde.Session.DynamicSupervisor))
    assert is_pid(Process.whereis(Tilde.Session.TaskSupervisor))
  end

  test "concurrent session startup returns one dynamically supervised server" do
    id = unique_id("startup-race")
    server = Registry.via(id)

    pids =
      1..10
      |> Task.async_stream(
        fn _ -> Server.ensure_started(server, session: Tilde.session(id: id)) end,
        max_concurrency: 10,
        ordered: false
      )
      |> Enum.map(fn {:ok, {:ok, pid}} -> pid end)

    assert [pid] = Enum.uniq(pids)
    stop_session_on_exit(pid)
    assert dynamic_session?(pid)
  end

  test "a crashed temporary session is removed and can be started again" do
    id = unique_id("restart")
    server = Registry.via(id)
    assert {:ok, first} = Server.ensure_started(server, session: Tilde.session(id: id))
    ref = Process.monitor(first)

    Process.exit(first, :kill)
    assert_receive {:DOWN, ^ref, :process, ^first, :killed}
    assert eventually(fn -> GenServer.whereis(server) == nil end)

    assert {:ok, second} = Server.ensure_started(server, session: Tilde.session(id: id))
    stop_session_on_exit(second)
    assert second != first
    assert dynamic_session?(second)
  end

  test "terminating a session also terminates its active agent task" do
    with_application_env(:llm_enabled, true, fn ->
      id = unique_id("task-cleanup")
      server = Registry.via(id)

      existing_tasks = Task.Supervisor.children(Tilde.Session.TaskSupervisor)

      assert {:ok, session} =
               Server.ensure_started(server,
                 session: Tilde.session(id: id),
                 llm_opts: [llm: blocking_llm(self())]
               )

      stop_session_on_exit(session)
      Server.append_event(server, Tilde.input_submitted("wait"))
      assert_receive {:supervised_llm_started, capability}, 1_000
      task = wait_for_supervised_task(existing_tasks)
      ref = Process.monitor(task)

      assert :ok = DynamicSupervisor.terminate_child(Tilde.Session.DynamicSupervisor, session)
      assert_receive {:DOWN, ^ref, :process, ^task, _reason}, 1_000
      send(capability, :release)
    end)
  end

  defp stop_session_on_exit(pid) do
    on_exit(fn ->
      if Process.alive?(pid) do
        DynamicSupervisor.terminate_child(Tilde.Session.DynamicSupervisor, pid)
      end
    end)
  end

  defp dynamic_session?(pid) do
    Tilde.Session.DynamicSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.any?(fn {_, child, _, _} -> child == pid end)
  end

  defp wait_for_supervised_task(existing_tasks, attempts \\ 20)

  defp wait_for_supervised_task(existing_tasks, attempts) when attempts > 0 do
    case Task.Supervisor.children(Tilde.Session.TaskSupervisor) -- existing_tasks do
      [task | _rest] ->
        task

      [] ->
        Process.sleep(10)
        wait_for_supervised_task(existing_tasks, attempts - 1)
    end
  end

  defp wait_for_supervised_task(_existing_tasks, 0),
    do: flunk("timed out waiting for supervised agent task")

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp eventually(fun, 0), do: fun.()

  defp blocking_llm(test_pid) do
    fn _intent, _journal ->
      send(test_pid, {:supervised_llm_started, self()})

      receive do
        :release -> {:ok, Jidoka.Effect.LLMDecision.final("released")}
      after
        5_000 -> {:error, :timeout}
      end
    end
  end

  defp unique_id(prefix),
    do: "#{prefix}-#{System.unique_integer([:positive])}"
end
