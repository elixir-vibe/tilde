defmodule Tilde.Session.LoaderTest do
  use TildeTest.Case, async: false

  alias Tilde.Session.Loader

  test "loads a persisted session when storage adapter is configured" do
    stored =
      Tilde.session(id: "stored")
      |> Session.append_event(Tilde.input_submitted("remembered"))
      |> Session.append_event(Tilde.input_changed("draft"))

    with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
      with_application_env(:storage_load_session, fn "stored" -> stored end, fn ->
        loaded = Loader.load_or_new("stored", new: fn -> Tilde.session(id: "fresh") end)

        assert loaded.id == "stored"
        assert latest_user_sources(loaded) == ["remembered"]
        assert loaded.input.value == "draft"
      end)
    end)
  end

  test "loads persisted compaction events as visible blocks and model context" do
    base =
      Tilde.session(id: "stored-compaction")
      |> Session.append_event(Tilde.input_submitted("one"))
      |> Session.append_event(Tilde.assistant_done("two"))
      |> Session.append_event(Tilde.input_submitted("three"))
      |> Session.append_event(Tilde.assistant_done("four"))

    first_kept_block_id = Enum.at(base.transcript.blocks, 2).id

    stored =
      Session.append_event(
        base,
        Tilde.context_compacted("## Context Compaction\n\nEarlier summary",
          metadata: %{first_kept_block_id: first_kept_block_id, tokens_before: 42}
        )
      )

    with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
      with_application_env(:storage_load_session, fn "stored-compaction" -> stored end, fn ->
        loaded = Loader.load_or_new("stored-compaction")

        assert List.last(loaded.transcript.blocks).kind == :compaction
        assert List.last(loaded.transcript.blocks).source =~ "Earlier summary"

        assert [summary | tail] = Tilde.Session.Compaction.model_context_blocks(loaded)
        assert summary.role == :system
        assert summary.source =~ "Earlier summary"
        assert Enum.map(tail, & &1.source) == ["three", "four"]
      end)
    end)
  end

  test "creates a fresh session when storage is disabled" do
    with_application_env(:storage_adapter, nil, fn ->
      assert %{id: "fresh"} =
               Loader.load_or_new("stored", new: fn -> Tilde.session(id: "fresh") end)
    end)
  end
end
