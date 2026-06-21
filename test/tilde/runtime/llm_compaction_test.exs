defmodule Tilde.Runtime.LLMCompactionTest do
  use TildeTest.Case

  alias Tilde.Core.Session
  alias Tilde.Runtime.LLM
  alias Tilde.Session.Compaction

  test "generic prompt uses compaction summary plus kept tail" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.input_submitted("one"))
      |> Session.append_event(Tilde.assistant_done("two"))
      |> Session.append_event(Tilde.input_submitted("three"))
      |> Session.append_event(Tilde.assistant_done("four"))
      |> Session.append_event(Tilde.input_submitted("five"))
      |> Session.append_event(Tilde.assistant_done("six"))

    assert {:ok, result} = Compaction.prepare(session, keep_recent_messages: 2)

    compacted =
      Session.append_event(
        session,
        Tilde.context_compacted(result.summary,
          metadata: %{first_kept_block_id: result.first_kept_block_id}
        )
      )

    prompt = LLM.prompt(compacted)

    assert prompt =~ "Compacted context:"
    assert prompt =~ "## Context Compaction"
    assert prompt =~ "User message: five"
    assert prompt =~ "Previous reply: six"
    refute prompt =~ "User message: one"
    refute prompt =~ "Previous reply: two"
  end
end
