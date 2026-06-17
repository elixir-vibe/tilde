defmodule TildeSSHDriverTest do
  use ExUnit.Case, async: false

  alias TildeTest.Driver.SSH

  test "real SSH driver types local prompt text and submits through the daemon" do
    state = SSH.open()

    try do
      state = SSH.type(state, "hello")
      assert SSH.text(state) =~ "> hello"

      state = SSH.press(state, :enter)
      assert [%{source: "hello"}] = wait_for_blocks(state)
    after
      SSH.close(state)
    end
  end

  test "real SSH driver renders slash suggestions for local prompt" do
    state = SSH.open()

    try do
      state = SSH.type(state, "/")
      assert SSH.text(state) =~ "commands"
      assert SSH.text(state) =~ "/attach"
    after
      SSH.close(state)
    end
  end

  defp wait_for_blocks(state, attempts \\ 10)
  defp wait_for_blocks(state, 0), do: SSH.session(state).transcript.blocks

  defp wait_for_blocks(state, attempts) do
    case SSH.session(state).transcript.blocks do
      [] ->
        Process.sleep(25)
        wait_for_blocks(state, attempts - 1)

      blocks ->
        blocks
    end
  end
end
