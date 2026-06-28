defmodule Tilde.Core.FileBufferTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.FileBuffer

  test "builds file buffer metadata from content" do
    buffer = FileBuffer.new(path: "lib/example.ex", content: "one\ntwo\n")

    assert buffer.path == "lib/example.ex"
    assert buffer.size == byte_size("one\ntwo\n")
    assert buffer.line_count == 3
    refute buffer.truncated?
    assert buffer.error == nil
    assert buffer.symbols == []
  end
end
