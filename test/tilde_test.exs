defmodule TildeTest do
  use ExUnit.Case
  doctest Tilde

  test "greets the world" do
    assert Tilde.hello() == :world
  end
end
