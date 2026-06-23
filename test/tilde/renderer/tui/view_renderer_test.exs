defmodule Tilde.Renderer.TUI.ViewRendererTest do
  use TildeTest.Case

  test "compaction renders as a visible collapsed terminal block" do
    session =
      Tilde.session()
      |> Tilde.Core.Session.append_event(
        Tilde.context_compacted("## Context Compaction\n\nSummary",
          metadata: %{tokens_before: 1234, first_kept_block_id: "msg_1"}
        )
      )

    rendered =
      session
      |> Tilde.Renderer.TUI.render_to_string(ansi: false, clear?: false)
      |> strip_ansi()

    assert rendered =~ "[compaction]"
    assert rendered =~ "Compacted from 1234 tokens (ctrl+o to expand)"
    refute rendered =~ "Summary"
  end

  test "expanded compaction renders summary in terminal block" do
    session =
      Tilde.session()
      |> Tilde.Core.Session.append_event(
        Tilde.context_compacted("## Context Compaction\n\nSummary",
          metadata: %{tokens_before: 1234, first_kept_block_id: "msg_1"}
        )
      )

    block_id = List.last(session.transcript.blocks).id
    session = Tilde.Core.Session.toggle_expand(session, block_id)

    rendered =
      session
      |> Tilde.Renderer.TUI.render_to_string(ansi: false, clear?: false)
      |> strip_ansi()

    assert rendered =~ "[compaction]"
    assert rendered =~ "Compacted from 1234 tokens"
    assert rendered =~ "Context Compaction"
    assert rendered =~ "Summary"
  end

  test "choice actions render from shared semantic actions" do
    choice = Tilde.choice("Proceed?", [{"yes", "Yes"}, {"no", "No"}])
    cell = Tilde.choice_block("choice_1", choice) |> Tilde.Viewable.to_view()

    rendered = cell |> Tilde.Renderer.TUI.ViewRenderer.render(60, ansi: false) |> strip_ansi()

    assert rendered =~ "Proceed?"
    assert rendered =~ "[ ] Yes"
    assert rendered =~ "enter Confirm    escape Cancel"
  end
end
