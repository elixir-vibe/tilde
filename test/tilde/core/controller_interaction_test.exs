defmodule Tilde.Core.ControllerInteractionTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.{Controller, Display, Interaction, Session}
  alias Tilde.Core.Interaction.Outcome

  test "session interactions edit suggestions and submit commands" do
    session = Tilde.session()

    assert {:cont, session, []} =
             Controller.apply_interaction(session, Interaction.input_changed("/"))

    assert Session.command_suggestions(session)

    assert {:cont, session, [%Outcome{type: :complete_input, payload: %{input: "/help"}}]} =
             Controller.apply_interaction(session, Interaction.new(:suggest_accept))

    assert session.input.value == "/help"

    assert {:cont, session, [%Outcome{type: :complete_input, payload: %{input: ""}}]} =
             Controller.apply_interaction(session, Interaction.new(:suggest_submit))

    assert session.input.value == ""
  end

  test "session interactions expose navigation effects for slash commands" do
    session = Tilde.session()

    assert {:cont, _session, [%Outcome{type: :open_session, payload: %{id: "demo"}}]} =
             Controller.apply_interaction(session, Interaction.submit("/new demo"))
  end

  test "session interactions preserve semantic component events" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.user_message("run"))
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "seq"}, tool_call_id: "tool_1")
      )
      |> Session.update_block("tool_1", &%{&1 | display: %Display{expanded?: false}})

    assert {:cont, session, []} =
             Controller.apply_interaction(
               session,
               Interaction.new(:toggle_expand, %{id: "tool_1"})
             )

    assert %{display: %{expanded?: true}} =
             Enum.find(session.transcript.blocks, &(&1.id == "tool_1"))
  end
end
