defmodule Tilde.Session.CompactionTest do
  use TildeTest.Case

  alias Tilde.Core.Session
  alias Tilde.Session.Compaction

  test "prepares a semantic summary without deleting events or visible transcript" do
    session = long_session()

    assert {:ok, result} = Compaction.prepare(session, keep_recent_messages: 2)
    assert result.summary =~ "## Context Compaction"
    assert result.summary =~ "User: one"
    assert result.first_kept_block_id == Enum.at(session.transcript.blocks, 4).id
    assert [_one, _two, _three, _four, _five, _six] = session.events
    assert [_one, _two, _three, _four, _five, _six] = session.transcript.blocks
  end

  test "model context uses latest compaction summary plus kept tail" do
    session = long_session()
    assert {:ok, result} = Compaction.prepare(session, keep_recent_messages: 2)

    compacted =
      Session.append_event(
        session,
        Tilde.context_compacted(result.summary,
          metadata: %{first_kept_block_id: result.first_kept_block_id}
        )
      )

    blocks = Compaction.model_context_blocks(compacted)

    assert Enum.map(blocks, & &1.role) == [:system, :user, :assistant]
    assert hd(blocks).source =~ "## Context Compaction"
    assert Enum.map(tl(blocks), & &1.source) == ["five", "six"]

    assert List.last(compacted.transcript.blocks).kind == :compaction

    assert Enum.map(compacted.transcript.blocks, & &1.source) == [
             "one",
             "two",
             "three",
             "four",
             "five",
             "six",
             result.summary
           ]
  end

  test "latest compaction supersedes earlier compaction for model context" do
    session = long_session()
    assert {:ok, first} = Compaction.prepare(session, keep_recent_messages: 4)

    session =
      Session.append_event(
        session,
        Tilde.context_compacted(first.summary,
          metadata: %{first_kept_block_id: first.first_kept_block_id}
        )
      )

    assert {:ok, second} = Compaction.prepare(session, keep_recent_messages: 2)

    session =
      Session.append_event(
        session,
        Tilde.context_compacted(second.summary,
          metadata: %{first_kept_block_id: second.first_kept_block_id}
        )
      )

    assert [summary | tail] = Compaction.model_context_blocks(session)
    assert summary.source == second.summary
    assert Enum.map(tail, & &1.source) == ["five", "six"]
  end

  defp long_session do
    Tilde.session()
    |> Session.append_event(Tilde.input_submitted("one"))
    |> Session.append_event(Tilde.assistant_done("two"))
    |> Session.append_event(Tilde.input_submitted("three"))
    |> Session.append_event(Tilde.assistant_done("four"))
    |> Session.append_event(Tilde.input_submitted("five"))
    |> Session.append_event(Tilde.assistant_done("six"))
  end
end
