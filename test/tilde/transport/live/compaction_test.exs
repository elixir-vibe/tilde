defmodule Tilde.Transport.Live.CompactionTest do
  use TildeTest.Case

  alias Tilde.Core.Session

  test "renders compaction as dedicated collapsed block" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.context_compacted("## Context Compaction\n\nSummary",
          metadata: %{tokens_before: 1234, first_kept_block_id: "msg_1"}
        )
      )

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)

    assert html =~ ~s|class="block compaction"|
    assert html =~ "[compaction]"
    assert html =~ "Compacted from 1234 tokens"
    assert html =~ "ctrl+o"
    refute html =~ "Summary"
  end

  test "expanded compaction block renders summary markdown" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.context_compacted("## Context Compaction\n\nSummary",
          metadata: %{tokens_before: 1234, first_kept_block_id: "msg_1"}
        )
      )

    block_id = List.last(session.transcript.blocks).id
    session = Session.toggle_expand(session, block_id)

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)

    assert html =~ "Summary"
    assert html =~ "collapse"
  end
end
