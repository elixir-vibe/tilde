defmodule Tilde.Renderer.TUITest do
  use TildeTest.Case

  test "uses algebra layout and IO.ANSI output" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_events([
        Tilde.user_message("Run tests", id: "evt_user"),
        Tilde.assistant_done("I'll run **them**.", id: "evt_assistant"),
        Tilde.tool_started("bash", %{command: "mix test", cwd: "/tmp/app"},
          tool_call_id: "tool_1"
        ),
        Tilde.tool_stream("tool_1", :stdout, "ok\n"),
        Tilde.tool_stream("tool_1", :stderr, "warning\n"),
        Tilde.tool_done("tool_1", :success, %{exit_code: 0})
      ])
      |> Session.put_status("model", "demo")

    rendered = Tilde.Renderer.TUI.render_to_string(session, width: 60)
    plain = strip_ansi(rendered)

    assert plain =~ "user\r\nRun tests"

    assert rendered =~ IO.ANSI.clear()
    assert rendered =~ IO.ANSI.home()
    assert rendered =~ IO.ANSI.green_background()
    assert rendered =~ "# tilde"

    assert rendered =~ "Run tests"
    assert rendered =~ "bash"
    assert rendered =~ "mix test"
    assert rendered =~ "stdout"
    assert rendered =~ "stderr"
    assert rendered =~ "warning"
    assert rendered =~ "model: demo"
    assert plain =~ "model: demo\r\n\r\n> "
    assert String.ends_with?(plain, "> ")
    refute plain =~ "▌"
    refute String.ends_with?(rendered, ["\n", "\r"])
  end

  test "can render ANSI without clearing normal terminal scrollback" do
    rendered =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Tilde.Renderer.TUI.render_to_string(width: 40, clear?: false)

    refute rendered =~ IO.ANSI.clear()
    refute rendered =~ IO.ANSI.home()
    assert rendered =~ "# tilde"
    assert strip_ansi(rendered) =~ "> "
  end

  test "clips full-frame output to terminal height" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_events([
        Tilde.user_message("one", id: "evt_one"),
        Tilde.assistant_done("two", id: "evt_two"),
        Tilde.user_message("three", id: "evt_three"),
        Tilde.assistant_turn_started(block_id: "msg_assistant_pending")
      ])

    rendered =
      session |> Tilde.Renderer.TUI.render_to_string(width: 40, height: 6) |> strip_ansi()

    refute rendered =~ "# tilde"
    refute rendered =~ "one"
    assert rendered =~ "three"
    assert rendered =~ "assistant\r\nthinking…\r\n\r\n> "
    assert String.ends_with?(rendered, "> ")
  end

  test "can render without ANSI for snapshots" do
    rendered =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Tilde.Renderer.TUI.render_to_string(width: 40, ansi: false)

    refute rendered =~ IO.ANSI.clear()
    assert rendered =~ "# tilde"
    assert rendered =~ "user"
    assert rendered =~ "hello"
    assert rendered =~ "> ▌"
  end
end
