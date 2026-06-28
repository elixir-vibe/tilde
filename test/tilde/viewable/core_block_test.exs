defmodule Tilde.Viewable.CoreBlockTest do
  use TildeTest.Case

  test "shared tool view cell drives LiveView and TUI text" do
    session =
      Tilde.session()
      |> Session.append_events([
        Tilde.tool_started("bash", %{command: "mix test", cwd: "/tmp/app"},
          tool_call_id: "tool_1"
        ),
        Tilde.tool_stream("tool_1", :stdout, "ok\n"),
        Tilde.tool_done("tool_1", :success, %{exit_code: 0})
      ])

    [block] = session.transcript.blocks
    cell = Tilde.Viewable.to_view(block)

    assert cell.attrs.template == :source
    live = render_component(&Tilde.Transport.Live.ViewRenderer.cell/1, cell: cell)
    live_text = strip_html(live)
    tui = cell |> Tilde.Renderer.TUI.ViewRenderer.render(60, ansi: true) |> strip_ansi()

    for line <- cell.lines do
      text = Tilde.View.Helpers.plain_text(line)
      assert live_text =~ text
      assert tui =~ text
    end
  end
end
