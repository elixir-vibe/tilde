defmodule Tilde.Tool.RegistryTest do
  use TildeTest.Case

  test "customizes semantic call and result views" do
    with_application_env(:tool_viewers, %{"custom_tool" => TildeTest.ToolRenderer}, fn ->
      session =
        Tilde.session()
        |> Session.append_events([
          Tilde.tool_started("custom_tool", %{value: "ok"}, tool_call_id: "tool_1"),
          Tilde.tool_done("tool_1")
        ])

      html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)
      tui = session |> Tilde.Renderer.TUI.render() |> Enum.join() |> strip_ansi()

      assert html =~ "custom"
      assert html =~ "ok"
      assert html =~ "[demo]"
      assert html =~ "custom result"
      assert tui =~ "custom ok [demo]"
      assert tui =~ "custom result"
    end)
  end
end
