defmodule TildeDriverTest do
  use ExUnit.Case, async: false

  alias Tilde.Core.Display
  alias TildeTest.Driver

  @drivers [TildeTest.Driver.Live, TildeTest.Driver.TUI]

  for driver <- @drivers do
    describe "#{inspect(driver)} slash command behavior" do
      setup do
        {:ok, driver: unquote(driver), state: unquote(driver).open()}
      end

      test "typing slash shows suggestions and selected command can be accepted", %{
        driver: driver,
        state: state
      } do
        state = Driver.type(driver, state, "/")

        suggest = Driver.session(driver, state) |> Tilde.Core.Session.command_suggestions()
        [first, second | _rest] = suggest.items

        Driver.assert_suggestion(driver, state, first.label, selected?: true)
        Driver.assert_text(driver, state, "commands")

        state = Driver.press(driver, state, :down)
        Driver.assert_suggestion(driver, state, second.label, selected?: true)

        state = Driver.press(driver, state, :enter)
        Driver.assert_input(driver, state, second.insert)
      end

      test "escape hides suggestions without clearing the input draft", %{
        driver: driver,
        state: state
      } do
        state = Driver.type(driver, state, "/")
        Driver.assert_suggestion(driver, state, "/attach")

        state = Driver.press(driver, state, :escape)

        Driver.assert_input(driver, state, "/")
        assert is_nil(Driver.session(driver, state) |> Tilde.Core.Session.command_suggestions())
      end
    end

    describe "#{inspect(driver)} prompt behavior" do
      setup do
        {:ok, driver: unquote(driver), state: unquote(driver).open()}
      end

      test "enter submits a non-empty input and clears the draft", %{driver: driver, state: state} do
        state =
          state
          |> then(&Driver.type(driver, &1, "hello"))
          |> then(&Driver.press(driver, &1, :enter))

        Driver.assert_input(driver, state, "")
        Driver.assert_text(driver, state, "hello")
      end

      test "ctrl-o expands compact tool output", %{driver: driver} do
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

        state = driver.open(session: session)
        Driver.assert_text(driver, state, "more lines")

        state = Driver.press(driver, state, :ctrl_o)
        Driver.assert_text(driver, state, "two")
      end
    end
  end
end
