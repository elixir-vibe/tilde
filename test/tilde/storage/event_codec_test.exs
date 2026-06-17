defmodule Tilde.Storage.EventCodecTest do
  use TildeTest.Case, async: true

  alias Tilde.Storage.EventCodec

  test "round-trips arbitrary event payload terms losslessly" do
    event =
      Tilde.tool_done("call-1", :success, {:ok, %{answer: [1, 2, 3]}},
        metadata: %{nested: {:tuple, :value}}
      )

    assert EventCodec.load!(EventCodec.dump(event)) == event
  end
end
