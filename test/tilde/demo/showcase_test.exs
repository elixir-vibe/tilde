defmodule Tilde.Demo.ShowcaseTest do
  use TildeTest.Case

  test "showcase command renders a complete dogfood console" do
    empty_demo = Tilde.Demo.Live.demo_session()
    session = Tilde.Demo.Showcase.append(empty_demo)
    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)

    tool_cell =
      session.transcript.blocks |> Enum.find(&(&1.kind == :tool)) |> Tilde.Viewable.to_view()

    assert tool_cell.attrs.template == :source
    assert html =~ "Build a pi-like console"
    assert html =~ "tool_demo_tests"
    refute html =~ "cwd ~/Development/elixir-vibe/tilde"
    refute html =~ "exit 0"
    assert html =~ ~s|class="block tool success"|
    refute html =~ "tool-status"
    refute html =~ "✓"
    assert html =~ ~s|class="key"|
    assert html =~ "ctrl+o"
    assert html =~ "expand"
    assert html =~ "Apply the generated patch?"
    assert html =~ ~s|class="header"|
    assert html =~ ~s|class="question"|
    assert html =~ ~s|class="footer actions"|
    assert html =~ ~s|class="option |
    assert html =~ ~s|id="dialog_demo"|
    assert html =~ "Dialog primitive"
    assert html =~ "shared web component and the TUI box renderer"
    refute html =~ "background: no running jobs"

    tui = session |> Tilde.Renderer.TUI.render_to_string(width: 72, ansi: false) |> strip_ansi()
    assert tui =~ "╭ Dialog primitive"
    assert tui =~ "enter Confirm    esc Cancel"

    effects = Tilde.Command.run(%Tilde.Command{name: "showcase"}, empty_demo, [])
    updated = Tilde.Command.apply_effects(empty_demo, effects)
    assert Enum.any?(updated.transcript.blocks, &(&1.source =~ "Build a pi-like console"))
  end
end
