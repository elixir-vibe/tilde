defmodule Tilde.Session.AgentLoopTest do
  use TildeTest.Case, async: true

  test "Jidoka data projection stays behind the runtime projection boundary" do
    source = File.read!("lib/tilde/session/agent_loop.ex")

    assert source =~ "JidokaEvent."
    refute source =~ "%Jidoka.Event{event: :turn_failed, data:"
    refute source =~ "event_field"
    refute source =~ "defp operation_result("
    refute source =~ "defp tool_status("
    refute source =~ "defp tool_result("
  end
end
