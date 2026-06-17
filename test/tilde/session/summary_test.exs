defmodule Tilde.Session.SummaryTest do
  use TildeTest.Case, async: false

  alias Tilde.Session.Summary

  test "includes persisted session summaries from storage" do
    persisted = Summary.from_texts("persisted", ["first persisted", "last persisted"])

    with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
      with_application_env(:storage_session_summaries, [persisted], fn ->
        assert [%Summary{id: "persisted", source: :persisted, row: row}] = Summary.list()
        assert row == "first persisted → last persisted"
      end)
    end)
  end
end
