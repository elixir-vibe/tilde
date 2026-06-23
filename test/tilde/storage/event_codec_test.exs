defmodule Tilde.Storage.EventCodecTest do
  use TildeTest.Case, async: true

  alias Tilde.Storage.EventCodec

  test "round-trips compaction events losslessly" do
    event =
      Tilde.context_compacted("## Context Compaction\n\nSummary",
        metadata: %{first_kept_block_id: "msg_1", tokens_before: 1234}
      )

    assert EventCodec.load!(EventCodec.dump(event)) == event
  end

  test "round-trips arbitrary event payload terms losslessly" do
    event =
      Tilde.tool_done("call-1", :success, {:ok, %{answer: [1, 2, 3]}},
        metadata: %{nested: {:tuple, :value}}
      )

    assert EventCodec.load!(EventCodec.dump(event)) == event
  end
end
