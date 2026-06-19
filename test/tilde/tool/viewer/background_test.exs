defmodule Tilde.Tool.Viewer.BackgroundTest do
  use TildeTest.Case

  alias Tilde.Core.Block
  alias Tilde.Tool.ViewModel

  test "renders pi-style display labels" do
    view =
      Block.tool("tool_1", "background-start", %{name: "demo-server", command: "mix phx.server"})
      |> ViewModel.view()

    assert view.name == "bg start"
    assert Enum.map(view.call_segments, & &1.text) == ["demo-server", "→ mix phx.server"]
  end
end
