defmodule Tilde.Tools.BashTest do
  use TildeTest.Case, async: false

  test "executes command and returns output with exit code" do
    assert {:ok, result} = Tilde.Tools.Bash.run(%{"command" => "printf hello"}, %{})

    assert %{content: [%{type: "text", text: "hello"}], exit_code: 0, duration_ms: duration} =
             result

    assert is_integer(duration)
  end

  test "non-zero exit remains a completed tool result" do
    assert {:ok, result} = Tilde.Tools.Bash.run(%{"command" => "echo nope; exit 7"}, %{})

    assert %{content: [%{text: "nope\n"}], exit_code: 7} = result
  end
end
