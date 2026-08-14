defmodule Tilde.Storage.QuackDBIntegrationTest do
  use TildeTest.Case, async: false

  alias Tilde.Core.Session
  alias Tilde.Session.Persistence
  alias Tilde.Storage
  alias Tilde.Storage.Setup

  @moduletag :quackdb_integration

  test "persists, searches, summarizes, and resumes sessions through QuackDB" do
    with_quackdb_repo(fn ->
      with_application_env(:storage_adapter, Tilde.Storage.QuackDB, fn ->
        draft_id = "quackdb-draft-#{System.unique_integer([:positive])}"
        empty = Tilde.session(id: draft_id)
        draft_only = Session.append_event(empty, Tilde.input_changed("unsent draft"))

        assert :ok = Persistence.persist(empty, draft_only)
        assert {:ok, restored_draft} = Storage.load_session(draft_id)
        assert restored_draft.input.value == "unsent draft"

        session_id = "quackdb-#{System.unique_integer([:positive])}"
        base = Tilde.session(id: session_id)
        submitted = Tilde.input_submitted("find ducks")
        persisted = Session.append_event(base, submitted)

        assert :ok = Persistence.persist(base, persisted)

        draft = Session.append_event(persisted, Tilde.input_changed("next draft"))
        sequenced = Session.append_event(draft, Tilde.status_changed("temporary", nil))

        assert :ok = Persistence.persist(persisted, sequenced)

        assert {:ok, loaded} = Storage.load_session(session_id)
        assert loaded |> Session.events() |> Enum.map(& &1.sequence) == [0, 2]
        assert loaded.next_event_sequence == 3
        assert latest_user_sources(loaded) == ["find ducks"]
        assert loaded.input.value == "next draft"

        assert {:ok, [%{session_id: ^session_id, text: "find ducks"}]} = Storage.search("ducks")

        assert {:ok, summaries} = Storage.session_summaries()
        assert Enum.any?(summaries, &(&1.id == session_id and &1.row == "find ducks"))
      end)
    end)
  end

  defp with_quackdb_repo(fun) do
    {uri, token} = quackdb_endpoint!()
    previous = Application.get_env(:tilde, Tilde.Storage.Repo)

    Application.put_env(:tilde, Tilde.Storage.Repo,
      uri: uri,
      token: token,
      pool_size: 1
    )

    try do
      assert {:ok, _versions} = Setup.migrate()
      start_supervised!({Tilde.Storage.Repo, []})
      fun.()
    after
      restore_application_env(Tilde.Storage.Repo, previous)
    end
  end

  defp quackdb_endpoint! do
    cond do
      uri = System.get_env("QUACKDB_TEST_URI") ->
        {uri, System.get_env("QUACKDB_TEST_TOKEN")}

      System.get_env("QUACKDB_TEST_DUCKDB") == "managed" ->
        start_managed_quackdb!()

      true ->
        raise "set QUACKDB_TEST_URI or QUACKDB_TEST_DUCKDB=managed"
    end
  end

  defp start_managed_quackdb! do
    port = 20_000 + rem(System.unique_integer([:positive, :monotonic]), 20_000)
    token = "tilde-test-#{System.unique_integer([:positive])}"
    name = Module.concat(__MODULE__, "Server#{System.unique_integer([:positive])}")

    start_supervised!(
      {QuackDB.Server,
       name: name,
       duckdb: :managed,
       endpoint: "quack:localhost:#{port}",
       token: token,
       wait_timeout: 120_000}
    )

    {QuackDB.Server.uri(name), token}
  end
end
