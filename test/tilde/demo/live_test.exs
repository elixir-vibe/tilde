defmodule Tilde.Demo.LiveTest do
  use TildeTest.Case

  test "demo session starts minimal" do
    empty_demo = Tilde.Demo.Live.demo_session()
    empty_html = render_component(&Tilde.Transport.Live.Console.console/1, session: empty_demo)

    assert empty_html =~ "/showcase"
    refute empty_html =~ "Build a pi-like console"
  end
end
