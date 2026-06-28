defmodule Tilde.Renderer.TUI.WorkspaceFileTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.FileBuffer
  alias Tilde.Renderer.TUI.WorkspaceFile

  test "centers an active line in the visible window" do
    rendered =
      long_file()
      |> WorkspaceFile.render(80, ansi: false, active_line: 30, viewport_height: 7)
      |> strip_ansi()

    assert rendered =~ "›  30 │ line 30"
    assert rendered =~ "   27 │ line 27"
    assert rendered =~ "   33 │ line 33"
    refute rendered =~ "line 1"
  end

  test "scroll line renders a manual viewport while preserving active marker if visible" do
    rendered =
      long_file()
      |> WorkspaceFile.render(80,
        ansi: false,
        active_line: 30,
        scroll_line: 28,
        viewport_height: 5
      )
      |> strip_ansi()

    assert rendered =~ "   28 │ line 28"
    assert rendered =~ "›  30 │ line 30"
    assert rendered =~ "   32 │ line 32"
    refute rendered =~ "line 27"
    refute rendered =~ "line 33"
  end

  defp long_file do
    content = Enum.map_join(1..60, "\n", &"line #{&1}")
    FileBuffer.new(path: "lib/long.ex", content: content)
  end
end
