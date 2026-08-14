defmodule Tilde.StorageTest do
  use TildeTest.Case, async: false

  alias Tilde.Storage

  test "defaults to a no-op storage boundary when no adapter is configured" do
    with_application_env(:storage_adapter, nil, fn ->
      session = Tilde.session(id: "storage-test")
      event = Tilde.input_submitted("remember this")

      assert :ok = Storage.ensure_session(session)
      assert :ok = Storage.append_event(session, event)
      assert :ok = Storage.save_state(session)
      assert {:ok, []} = Storage.load_events(session.id)
      assert {:ok, loaded} = Storage.load_session(session.id)
      assert loaded.id == "storage-test"
      assert Session.events(loaded) == []
      assert {:ok, []} = Storage.session_summaries()
      assert {:ok, []} = Storage.search("remember")
    end)
  end
end
