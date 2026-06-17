defmodule Tilde.Core.ControllerInteractionTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.{Controller, Display, Interaction, Session}

  test "session interactions edit suggestions and submit commands" do
    session = Tilde.session()

    result = Controller.apply_interaction(session, Interaction.input_changed("/"))

    assert_interaction_cont(result)
    assert Session.command_suggestions(elem(result, 1))

    result = Controller.apply_interaction(elem(result, 1), Interaction.new(:suggest_accept))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:complete_input, input: "/help")
    |> assert_interaction_input("/help")

    result = Controller.apply_interaction(elem(result, 1), Interaction.new(:suggest_submit))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:complete_input, input: "")
    |> assert_interaction_input("")
  end

  test "session interactions expose navigation effects for slash commands" do
    session = Tilde.session()

    session
    |> Controller.apply_interaction(Interaction.submit("/new demo"))
    |> assert_interaction_cont()
    |> assert_outcome(:open_session, id: "demo")
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
