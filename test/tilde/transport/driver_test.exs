defmodule TildeDriverTest do
  use TildeTest.TransportCase, async: false

  alias Tilde.Core.Display

  @drivers TildeTest.TransportCase.fast_drivers()

  for driver <- @drivers do
    describe "#{inspect(driver)} slash command behavior" do
      setup do
        {:ok, state: Driver.open(unquote(driver))}
      end

      test "typing slash shows suggestions, tab completes, and enter executes", %{state: state} do
        state = Driver.type(state, "/")

        suggest = Driver.session(state) |> Tilde.Core.Session.command_suggestions()
        [first, second | _rest] = suggest.items

        state =
          state
          |> Driver.assert_suggestion(first.label, selected?: true)
          |> Driver.assert_text("commands")
          |> Driver.press(:down)
          |> Driver.assert_suggestion(second.label, selected?: true)
          |> Driver.press(:tab)
          |> Driver.assert_input(second.insert)

        state
        |> Driver.press(:enter)
        |> Driver.assert_input("")
        |> Driver.refute_suggestions()
      end

      test "selection is preserved across query filtering", %{state: state} do
        state =
          state
          |> Driver.type("/")
          |> Driver.press(:down)

        selected =
          Driver.session(state)
          |> Tilde.Core.Session.command_suggestions()
          |> Tilde.Core.Suggest.selected()

        state = Driver.type(state, String.replace_prefix(selected.label, "/", ""))

        Driver.assert_suggestion(state, selected.label, selected?: true)
      end

      test "escape hides suggestions without clearing the input draft", %{state: state} do
        state
        |> Driver.type("/")
        |> Driver.assert_suggestion("/attach")
        |> Driver.press(:escape)
        |> Driver.assert_input("/")
        |> Driver.refute_suggestions()
      end
    end

    describe "#{inspect(driver)} prompt behavior" do
      setup do
        {:ok, state: Driver.open(unquote(driver))}
      end

      test "enter submits a non-empty input and clears the draft", %{state: state} do
        state
        |> Driver.step("Submit hello", fn state ->
          state
          |> Driver.type("hello")
          |> Driver.press(:enter)
        end)
        |> Driver.assert_input("")
        |> Driver.assert_text("hello")
      end

      test "ctrl-o expands compact tool output" do
        session =
          Tilde.session()
          |> Tilde.Core.Session.append_event(Tilde.user_message("run"))
          |> Tilde.Core.Session.append_event(
            Tilde.tool_started("bash", %{command: "seq"}, tool_call_id: "tool_1")
          )
          |> Tilde.Core.Session.update_block(
            "tool_1",
            &%{&1 | display: %Display{compact_limit: {:lines, 1}}}
          )
          |> Tilde.Core.Session.append_event(Tilde.tool_stream("tool_1", :stdout, "one\ntwo\n"))

        unquote(driver)
        |> Driver.open(session: session)
        |> Driver.assert_tool("bash")
        |> Driver.assert_collapsed("bash")
        |> Driver.assert_text("more lines")
        |> Driver.press(:ctrl_o)
        |> Driver.assert_expanded("bash")
        |> Driver.assert_text("two")
      end

      test "pending assistant status is visible" do
        session =
          Tilde.session()
          |> Tilde.Core.Session.append_event(
            Tilde.assistant_turn_started(block_id: "msg_assistant_pending")
          )

        unquote(driver)
        |> Driver.open(session: session)
        |> Driver.assert_pending()
      end
    end
  end
end
