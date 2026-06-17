defmodule Tilde.Storage.EventPolicyTest do
  use TildeTest.Case, async: true

  alias Tilde.Storage.EventPolicy

  test "keeps draft-only input changes out of the canonical durable event log" do
    refute EventPolicy.persist?(Tilde.input_changed("draft"))
    assert EventPolicy.persist?(Tilde.input_submitted("hello"))
    assert EventPolicy.persist?(Tilde.assistant_delta("hi"))
    assert EventPolicy.persist?(Tilde.tool_done("tool-1"))
  end
end
