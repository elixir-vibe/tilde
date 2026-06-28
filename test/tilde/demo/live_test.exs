defmodule Tilde.Demo.LiveTest do
  use TildeTest.Case

  test "index footer renders the same shared clickable commands as session footer" do
    html =
      render_component(&Tilde.Transport.Live.WidgetRenderer.widgets/1,
        widgets: Tilde.Index.View.widgets(Tilde.Core.Index.new())
      )

    assert html =~ ~s|role="navigation"|
    assert html =~ ~s|aria-label="commands"|
    assert html =~ ~s|phx-click="tilde:complete_input"|
    assert html =~ ~s|phx-value-insert="/help"|
    assert html =~ ~s|phx-value-insert="/showcase"|
    assert html =~ ~s|phx-value-insert="/new "|
    assert html =~ "/help"
    assert html =~ "/showcase"
    assert html =~ "/new"
  end

  test "demo session starts minimal" do
    empty_demo = Tilde.Demo.Live.demo_session()
    empty_html = render_component(&Tilde.Transport.Live.Console.console/1, session: empty_demo)

    assert empty_html =~ "/showcase"
    refute empty_html =~ "Build a pi-like console"
  end
end
