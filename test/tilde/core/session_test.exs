defmodule Tilde.Core.SessionTest do
  use TildeTest.Case

  test "keeps event log, transcript, widgets, and statuses" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Session.put_widget(Tilde.widget("logs", :below_input, ["server running"]))
      |> Session.put_status("model", "sonnet")

    assert session.id == "session_1"
    assert [_event] = Session.events(session)
    assert [%Block{source: "hello"}] = session.transcript.blocks
    assert [%{id: "logs"}] = Session.widgets(session, :below_input)
    assert session.statuses["model"] == "sonnet"
  end

  test "appends batches of events in order" do
    events = [
      Tilde.input_submitted("one", id: "evt_one"),
      Tilde.assistant_done("two", id: "evt_two")
    ]

    session = Session.append_events(Tilde.session(), events)

    assert session |> Session.events() |> Enum.map(&{&1.sequence, &1.id}) == [
             {0, "evt_one"},
             {1, "evt_two"}
           ]

    assert Enum.map(session.event_log, & &1.id) == ["evt_two", "evt_one"]
    assert Enum.map(Session.events_since(session, 1), & &1.id) == ["evt_two"]
    assert session.event_count == 2
    assert session.next_event_sequence == 2
    assert [%Block{source: "one"}, %Block{source: "two"}] = session.transcript.blocks
  end

  test "restores ordered canonical events when ephemeral sequence positions are absent" do
    events = [
      Tilde.input_submitted("one", sequence: 1),
      Tilde.assistant_done("two", sequence: 3)
    ]

    session = Session.append_events(Tilde.session(), events)

    assert session |> Session.events() |> Enum.map(& &1.sequence) == [1, 3]
    assert session |> Session.events_since(2) |> Enum.map(& &1.sequence) == [3]
    assert session.event_count == 2
    assert session.next_event_sequence == 4
  end

  test "rejects newly appended events that do not continue the canonical sequence" do
    session = Session.append_event(Tilde.session(), Tilde.input_submitted("one"))

    assert_raise ArgumentError, ~r/event sequence 3 does not follow session sequence 1/, fn ->
      Session.append_event(session, Tilde.input_submitted("out of order", sequence: 3))
    end
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
