defmodule Tilde.Transport.Live.FooterTest do
  use TildeTest.Case, async: true

  test "renders shared footer actions" do
    html =
      render_component(&Tilde.Transport.Live.Footer.footer/1,
        left: "10 lines · 100 bytes",
        actions: [%{event: "tilde:session:chat", label: "chat", key: "esc"}]
      )

    assert html =~ ~s|class="footer"|
    assert html =~ "10 lines · 100 bytes"
    assert html =~ ~s|class="actions"|
    assert html =~ ~s|phx-click="tilde:session:chat"|
    assert html =~ "esc"
    assert html =~ "chat"
  end
end
