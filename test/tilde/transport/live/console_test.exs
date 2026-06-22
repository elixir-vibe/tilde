defmodule Tilde.Transport.Live.ConsoleTest do
  use TildeTest.Case

  test "pending empty tool blocks show waiting without status badges" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)
    tui = session |> Tilde.Renderer.TUI.render() |> Enum.join()

    assert html =~ "bash"
    assert html =~ "mix test"
    assert html =~ "Waiting…"
    refute html =~ "tool-status"
    assert tui =~ "Waiting…"
  end

  test "shows pending assistant directly after transcript" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.assistant_turn_started(block_id: "msg_assistant_pending"))

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)

    assert html =~ "pending"
    assert html =~ "assistant"
    assert html =~ "thinking…"
    refute html =~ "model: thinking"
    assert html =~ "interrupt"
  end

  test "hides pending assistant once streaming starts" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_events([
        Tilde.assistant_turn_started(block_id: "msg_assistant_pending"),
        Tilde.assistant_delta("hello", block_id: "msg_assistant_pending")
      ])

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)

    refute html =~ "pending"
    refute html =~ "thinking…"
    assert html =~ "hello"
  end

  test "renders footer commands as shared complete-input actions" do
    commands = [
      Tilde.Command.Builtin.Help.spec(),
      Tilde.Command.Builtin.Showcase.spec(),
      Tilde.Command.Builtin.New.spec()
    ]

    html =
      render_component(&Tilde.Transport.Live.Console.console/1,
        session: Tilde.session(id: "session_1"),
        footer_commands: commands
      )

    assert html =~ ~s|role="navigation"|
    assert html =~ ~s|aria-label="commands"|
    assert html =~ ~s|class="action normal"|
    assert html =~ ~s|phx-click="tilde:complete_input"|
    assert html =~ ~s|phx-value-insert="/help"|
    assert html =~ ~s|phx-value-insert="/showcase"|
    assert html =~ ~s|phx-value-insert="/new "|
  end

  test "renders transcript, widgets, input, and footer" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_events([
        Tilde.user_message("Run tests", id: "evt_user"),
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1"),
        Tilde.tool_stream("tool_1", :stdout, "ok\n"),
        Tilde.tool_done("tool_1")
      ])
      |> Session.put_widget(Tilde.widget("logs", :below_input, ["server running"]))
      |> Session.put_status("model", "sonnet")

    html =
      render_component(&Tilde.Transport.Live.Console.console/1, session: session, input: "next")

    assert html =~ "phx-hook=\"TildeConsole\""
    assert html =~ ~s|class="tilde |
    assert html =~ "Run tests"
    assert html =~ "bash"
    assert html =~ "mix test"
    assert html =~ "ok"
    assert html =~ "server running"
    assert html =~ ~s|class="left muted"|
    assert html =~ "session: session_1"
    assert html =~ "model: sonnet"
  end
end
