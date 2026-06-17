defmodule Tilde.Rendering.TemplateToolDemoTest do
  use TildeTest.Case

  test "text renderer produces pi-like transcript snapshots" do
    transcript =
      [
        Tilde.user_message("Run tests", id: "evt_user"),
        Tilde.assistant_done("I'll run them.", id: "evt_assistant"),
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1"),
        Tilde.tool_stream("tool_1", :stdout, "ok\n"),
        Tilde.tool_done("tool_1")
      ]
      |> Transcript.from_events()

    assert Renderer.Text.render(transcript) ==
             """
             user
               Run tests

             assistant
               I'll run them.

             bash mix test success
             ok
             """
             |> String.trim_trailing()
  end

  test "session can trim event log and rebuild derived state" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.input_submitted("one"))
      |> Session.append_event(Tilde.assistant_done("two"))
      |> Session.append_event(Tilde.input_submitted("three"))
      |> Session.trim_events(2)

    assert Enum.map(session.events, & &1.text) == ["two", "three"]
    assert Enum.map(session.transcript.blocks, & &1.source) == ["two", "three"]
  end

  test "session server applies configured event trimming" do
    with_application_env(:llm_enabled, false, fn ->
      with_application_env(:session_event_limit, 2, fn ->
        name = :"tilde_session_server_trim_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "trim_test")
                 )

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("one"))
        Tilde.Session.Server.append_event(name, Tilde.assistant_done("two"))
        updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("three"))

        assert Enum.map(updated.events, & &1.text) == ["two", "three"]
        assert Enum.map(updated.transcript.blocks, & &1.source) == ["two", "three"]

        GenServer.stop(pid)
      end)
    end)
  end

  test "session keeps event log, transcript, widgets, and statuses" do
    session =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Session.put_widget(Tilde.widget("logs", :below_input, ["server running"]))
      |> Session.put_status("model", "sonnet")

    assert session.id == "session_1"
    assert [_event] = session.events
    assert [%Block{source: "hello"}] = session.transcript.blocks
    assert [%{id: "logs"}] = Session.widgets(session, :below_input)
    assert session.statuses["model"] == "sonnet"
  end

  test "session updates blocks for LiveView event handlers" do
    choice = Tilde.choice("Pick one", [{"a", "A"}, {"b", "B"}])

    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )
      |> Session.update_block("tool_1", &Block.update_display(&1, %{compact_limit: {:lines, 1}}))
      |> then(fn session ->
        transcript = %{
          session.transcript
          | blocks: session.transcript.blocks ++ [Block.choice("choice_1", choice)]
        }

        %{session | transcript: transcript}
      end)
      |> Session.toggle_expand("tool_1")
      |> Session.select_choice("choice_1", "b")

    assert [%Block{display: %{expanded?: true}}, %Block{choice: selected_choice}] =
             session.transcript.blocks

    assert selected_choice.selected == ["b"]
  end

  test "choice blocks model pi-like selection without renderer coupling" do
    choice =
      "Proceed?"
      |> Tilde.choice([{"yes", "Yes"}, {"no", "No"}], selected: ["yes"])
      |> Choice.select("no")

    block = Tilde.choice_block("choice_1", choice)

    assert block.kind == :choice
    assert block.choice.selected == ["no"]
    assert Enum.map(block.actions, & &1.id) == [:confirm, :cancel]
  end

  test "Tilde semantic HEEx components render to cells, LiveView, and TUI" do
    require Tilde.Template
    require Tilde.Template.Renderer.Live
    require Tilde.Template.Renderer.TUI

    source = """
    <.cell kind="template" state="success" padding_x={1} padding_y={0}>
      <.tool_call name="bash" segment="mix test" />
      <.line role="metadata"><.meta>cwd /tmp/app  exit 0</.meta></.line>
      <.line role="primary"><.primary>ok</.primary></.line>
    </.cell>
    """

    [cell] = Tilde.Template.to_cells!(source)

    assert cell.kind == :template
    assert cell.state == :success
    assert cell.padding_x == 1

    assert Enum.map(cell.lines, &Tilde.View.Helpers.plain_text/1) == [
             "bash mix test",
             "cwd /tmp/app  exit 0",
             "ok"
           ]

    assert [%{style: :title}, %{style: :accent}] = hd(cell.lines).parts
    assert List.last(cell.lines).role == :primary

    live = source |> Tilde.Template.Renderer.Live.render!() |> rendered_to_string()
    tui = Tilde.Template.Renderer.TUI.render!(source, 50)

    assert live =~ ~s|class="text title"|
    assert live =~ ~s|class="text accent"|
    assert strip_ansi(tui) =~ "bash mix test"
    assert strip_ansi(tui) =~ "ok"
    assert tui =~ IO.ANSI.bright()
  end

  test "Tilde semantic HEEx templates support assigns, message cells, and markdown" do
    require Tilde.Template
    require Tilde.Template.Renderer.Live
    require Tilde.Template.Renderer.TUI

    source = """
    <.message role={@role}>
      Hello <.title>{@name}</.title>
    </.message>
    <.markdown role="assistant">
      **streaming** markdown
    </.markdown>
    """

    [message, markdown] = Tilde.Template.to_cells!(source, assigns: %{role: "user", name: "Ada"})

    assert message.kind == :message
    assert message.role == :user
    assert message.source == "Hello Ada"
    assert Enum.any?(hd(message.lines).parts, &(&1.style == :title and &1.text == "Ada"))

    assert markdown.kind == :message
    assert markdown.role == :assistant
    assert markdown.format == :markdown
    assert markdown.source == "**streaming** markdown"

    live =
      source
      |> Tilde.Template.Renderer.Live.render!(assigns: %{role: "user", name: "Ada"})
      |> rendered_to_string()

    tui = Tilde.Template.Renderer.TUI.render!(source, 50, assigns: %{role: "user", name: "Ada"})

    assert live =~ "Hello"
    assert strip_ansi(tui) =~ "Hello Ada"
  end

  test "Tilde semantic HEEx source walker supports lists, code blocks, and tables" do
    require Tilde.Template

    [cell] =
      Tilde.Template.to_cells!("""
      <.cell>
        <ul><li>one</li><li><strong>two</strong></li></ul>
        <pre>mix test\nok</pre>
        <table>
          <tr><th>Name</th><th>Status</th></tr>
          <tr><td>CI</td><td><.success>green</.success></td></tr>
        </table>
      </.cell>
      """)

    assert Enum.map(cell.lines, &Tilde.View.Helpers.plain_text/1) == [
             "• one",
             "• two",
             "mix test",
             "ok",
             "Name | Status",
             "CI | green"
           ]

    assert [
             %{style: :title, text: "Name"},
             %{style: :muted, text: " | "},
             %{style: :title, text: "Status"}
           ] = Enum.at(cell.lines, 4).parts

    assert Enum.any?(List.last(cell.lines).parts, &(&1.style == :success and &1.text == "green"))
  end

  test "Tilde semantic HEEx templates report missing assigns" do
    require Tilde.Template

    assert_raise KeyError, fn ->
      Tilde.Template.to_cells!("""
      <.message>Hello {@missing}</.message>
      """)
    end
  end

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

    refute live_text =~ "cwd /tmp/app"
    refute live_text =~ "exit 0"
    refute tui =~ "cwd /tmp/app"
    refute tui =~ "exit 0"

    for line <- cell.lines do
      text = Tilde.View.Helpers.plain_text(line)
      assert live_text =~ text
      assert tui =~ text
    end
  end

  test "tool result wrapper normalizes successes errors and exceptions" do
    assert Tilde.Tool.Result.run(fn -> "ok" end) == {:ok, "ok"}
    assert Tilde.Tool.Result.run(fn -> {:error, :boom} end) == {:error, :boom}
    assert {:error, formatted} = Tilde.Tool.Result.run(fn -> raise "boom" end)
    assert formatted =~ "boom"
  end

  test "tool lifecycle event normalizes finished outputs" do
    event = Tilde.Tool.Event.finished(id: "tool_1", name: "demo", output: {:error, :boom})

    assert event.id == "tool_1"
    assert event.name == "demo"
    assert event.output == %{error: :boom}
    assert event.status == :error
    assert event.phase == :finished
  end

  test "tool renderer registry customizes semantic call and result views" do
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

  test "demo session starts minimal and showcase command renders a complete dogfood console" do
    empty_demo = Tilde.Demo.Live.demo_session()
    empty_html = render_component(&Tilde.Transport.Live.Console.console/1, session: empty_demo)

    assert empty_html =~ "/showcase"
    refute empty_html =~ "Build a pi-like console"

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
    refute html =~ "background: no running jobs"

    effects = Tilde.Command.run(%Tilde.Command{name: "showcase"}, empty_demo, [])
    updated = Tilde.Command.apply_effects(empty_demo, effects)
    assert Enum.any?(updated.transcript.blocks, &(&1.source =~ "Build a pi-like console"))
  end

  test "demo password is generated once when not configured" do
    previous = Application.get_env(:tilde, :demo_password)
    Application.delete_env(:tilde, :demo_password)

    first = Tilde.Demo.Password.get()
    second = Tilde.Demo.Password.get()

    assert first == second
    assert byte_size(first) >= 32
    assert Tilde.Demo.Password.valid?(first)

    restore_application_env(:demo_password, previous)
  end

  test "demo health endpoint is unauthenticated" do
    conn =
      :get
      |> conn("/healthz")
      |> Tilde.Demo.Router.call([])

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end

  test "web demo requires password session" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :get
        |> conn("/tilde")
        |> init_test_session(%{})
        |> Tilde.Demo.Router.call([])

      assert conn.status == 302
      assert [location] = Plug.Conn.get_resp_header(conn, "location")
      assert location =~ "/login?return_to=%2Ftilde"
    end)
  end

  test "web demo login accepts configured password" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Demo.Auth.create(%{
          "password" => "secret",
          "return_to" => "/tilde/auth-smoke"
        })

      assert conn.status == 302
      assert Plug.Conn.get_session(conn, :tilde_demo_authenticated) == true
      assert Plug.Conn.get_resp_header(conn, "location") == ["/tilde/auth-smoke"]
    end)
  end

  test "web demo login rejects protocol-relative return paths" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Demo.Auth.create(%{
          "password" => "secret",
          "return_to" => "//evil.example/path"
        })

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/tilde"]
    end)
  end

  test "web demo login rejects wrong password" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Demo.Auth.create(%{"password" => "wrong", "return_to" => "/tilde"})

      assert conn.status == 401
      refute Plug.Conn.get_session(conn, :tilde_demo_authenticated)
      assert conn.resp_body =~ "Incorrect password"
    end)
  end

  test "live console shows pending assistant directly after transcript" do
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

  test "live console hides pending assistant once streaming starts" do
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

  test "live console renders transcript, widgets, input, and footer" do
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

  test "json renderer returns JSON-compatible semantic data" do
    transcript =
      [
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1"),
        Tilde.tool_stream("tool_1", :stdout, "ok\n")
      ]
      |> Transcript.from_events()

    rendered = Renderer.JSON.render(transcript)

    assert [%{kind: :tool, streams: [stream]}] = rendered.blocks
    assert stream.text == "ok\n"
    assert stream.line_count == 1
    assert stream.byte_count == 3
  end
end
