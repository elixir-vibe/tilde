defmodule Tilde.Core.SessionTest do
  use TildeTest.Case

  test "can trim event log and rebuild derived state" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.input_submitted("one"))
      |> Session.append_event(Tilde.assistant_done("two"))
      |> Session.append_event(Tilde.input_submitted("three"))
      |> Session.trim_events(2)

    assert Enum.map(session.events, & &1.text) == ["two", "three"]
    assert Enum.map(session.transcript.blocks, & &1.source) == ["two", "three"]
  end

  test "keeps event log, transcript, widgets, and statuses" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Session.put_widget(Tilde.widget("logs", :below_input, ["server running"]))
      |> Session.put_status("model", "sonnet")

    assert session.id == "session_1"
    assert [_event] = session.events
    assert [%Block{source: "hello"}] = session.transcript.blocks
    assert [%{id: "logs"}] = Session.widgets(session, :below_input)
    assert session.statuses["model"] == "sonnet"
  end

  test "toggles tool expansion as one semantic group" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.tool_started("bash", %{}, tool_call_id: "tool_1"))
      |> Session.append_event(Tilde.tool_started("read", %{}, tool_call_id: "tool_2"))
      |> Session.toggle_expand("tool_1")
      |> Session.toggle_tool_expansion()

    assert [%Block{display: %{expanded?: true}}, %Block{display: %{expanded?: true}}] =
             session.transcript.blocks

    session = Session.toggle_tool_expansion(session)

    assert [%Block{display: %{expanded?: false}}, %Block{display: %{expanded?: false}}] =
             session.transcript.blocks
  end

  test "updates blocks for LiveView event handlers" do
    choice = Tilde.choice("Pick one", [{"a", "A"}, {"b", "B"}])

    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )
      |> Session.update_block("tool_1", &Block.update_display(&1, %{compact_limit: {:lines, 1}}))
      |> then(fn session ->
        transcript = %{
          session.transcript
          | blocks: session.transcript.blocks ++ [Block.choice("choice_1", choice)]
        }

        %{session | transcript: transcript}
      end)
      |> Session.toggle_expand("tool_1")
      |> Session.select_choice("choice_1", "b")

    assert [%Block{display: %{expanded?: true}}, %Block{choice: selected_choice}] =
             session.transcript.blocks

    assert selected_choice.selected == ["b"]
  end
end
