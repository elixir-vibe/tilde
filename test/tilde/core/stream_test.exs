defmodule Tilde.Core.StreamTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Stream

  test "returns appended text without joining unchanged history" do
    old =
      Stream.new(:stdout)
      |> Stream.append("one\n")
      |> Stream.append("two\n")

    new = Stream.append(old, "three\n")

    assert Stream.appended_text(old, new) == {"three\n", false}
    assert Stream.appended_text(Stream.new(:stdout), new) == {"one\ntwo\nthree\n", true}
  end

  test "returns nil for non-append stream changes" do
    old = Stream.new(:stdout) |> Stream.append("one\n")
    new = Stream.new(:stdout) |> Stream.append("different\n")

    assert Stream.appended_text(old, new) == nil
  end
end
