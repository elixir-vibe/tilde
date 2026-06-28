defmodule Tilde.Core.AssistantTurnTest do
  use TildeTest.Case, async: true

  alias ReqLLM.StreamChunk
  alias Tilde.Core.AssistantTurn

  test "exposes chunks in chronological order" do
    turn =
      AssistantTurn.waiting("msg_assistant")
      |> AssistantTurn.apply_chunk(StreamChunk.text("one"))
      |> AssistantTurn.apply_chunk(StreamChunk.text("two"))

    assert Enum.map(AssistantTurn.chunks(turn), & &1.text) == ["one", "two"]
  end
end
