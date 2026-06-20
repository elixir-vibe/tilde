defmodule Tilde.Tool.ResultTest do
  use TildeTest.Case

  test "normalizes successes errors and exceptions" do
    assert Tilde.Tool.Result.run(fn -> "ok" end) == {:ok, "ok"}
    assert Tilde.Tool.Result.run(fn -> {:error, :boom} end) == {:error, :boom}
    assert {:error, formatted} = Tilde.Tool.Result.run(fn -> raise "boom" end)
    assert formatted =~ "boom"
  end
end
