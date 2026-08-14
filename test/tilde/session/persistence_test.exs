defmodule TildeTest.FaultStorageAdapter do
  @behaviour Tilde.Storage

  @impl true
  def ensure_session(_session), do: reply(:ensure_session)

  @impl true
  def append_event(_session, _event), do: reply(:append_event)

  @impl true
  def save_state(_session), do: reply(:save_state)

  @impl true
  def load_events(_session_id), do: {:ok, []}

  @impl true
  def load_session(session_id), do: {:ok, Tilde.session(id: session_id)}

  @impl true
  def session_summaries(_opts), do: {:ok, []}

  @impl true
  def search(_query, _opts), do: {:ok, []}

  defp reply(operation) do
    if Application.get_env(:tilde, :storage_fault) == operation do
      {:error, {:injected_failure, operation}}
    else
      :ok
    end
  end
end

defmodule Tilde.Session.PersistenceTest do
  use TildeTest.Case, async: false

  import ExUnit.CaptureLog

  alias Tilde.Session.Persistence
  alias Tilde.Storage.Error

  setup do
    previous_adapter = Application.get_env(:tilde, :storage_adapter)
    previous_fault = Application.get_env(:tilde, :storage_fault)
    Application.put_env(:tilde, :storage_adapter, TildeTest.FaultStorageAdapter)

    on_exit(fn ->
      restore_application_env(:storage_adapter, previous_adapter)
      restore_application_env(:storage_fault, previous_fault)
    end)
  end

  test "fails explicitly when session initialization cannot be stored" do
    previous = Tilde.session(id: "ensure-failure")
    current = Session.append_event(previous, Tilde.input_submitted("hello"))
    Application.put_env(:tilde, :storage_fault, :ensure_session)

    assert_raise Error, ~r/storage ensure_session failed/, fn ->
      Persistence.persist(previous, current)
    end
  end

  test "fails explicitly when a canonical event cannot be appended" do
    previous = Tilde.session(id: "append-failure")
    current = Session.append_event(previous, Tilde.input_submitted("hello"))
    Application.put_env(:tilde, :storage_fault, :append_event)

    assert_raise Error, ~r/storage append_event failed/, fn ->
      Persistence.persist(previous, current)
    end
  end

  test "fails explicitly when resumable state cannot be saved" do
    previous = Tilde.session(id: "state-failure")
    current = Session.append_event(previous, Tilde.input_changed("draft"))
    Application.put_env(:tilde, :storage_fault, :save_state)

    assert_raise Error, ~r/storage save_state failed/, fn ->
      Persistence.persist(previous, current)
    end
  end

  test "a session server does not acknowledge an event that storage rejected" do
    previous_trap = Process.flag(:trap_exit, true)
    Application.put_env(:tilde, :storage_fault, :append_event)
    name = :"persistence-failure-#{System.unique_integer([:positive])}"

    try do
      log =
        capture_log(fn ->
          assert {:ok, server} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "server-write-failure")
                   )

          monitor = Process.monitor(server)

          assert catch_exit(
                   Tilde.Session.Server.append_event(name, Tilde.input_submitted("rejected"))
                 )

          assert_receive {:DOWN, ^monitor, :process, ^server,
                          {%Error{operation: :append_event}, _stacktrace}}
        end)

      assert log =~ "Tilde storage append_event failed"
    after
      Process.flag(:trap_exit, previous_trap)
    end
  end
end
