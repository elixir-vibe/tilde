defmodule Tilde.Tool.EventTest do
  use TildeTest.Case

  test "normalizes finished outputs" do
    event = Tilde.Tool.Event.finished(id: "tool_1", name: "demo", output: {:error, :boom})

    assert event.id == "tool_1"
    assert event.name == "demo"
    assert event.output == %{error: :boom}
    assert event.status == :error
    assert event.phase == :finished
  end
end
