defmodule Tilde.Rendering.LiveMarkdownTuiTest do
  use TildeTest.Case

  test "live tool renders through shared semantic view cells" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test", cwd: "/tmp/app"},
        display: %Display{compact_limit: {:lines, 3}}
      )
      |> Block.append_stream(:stdout, "ok\n")
      |> Block.append_stream(:stderr, "warning\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    html = render_component(&Tilde.Transport.Live.Tool.tool/1, block: tool)

    assert html =~ ~s|class="lines"|
    assert html =~ ~s|class="text muted">stdout|
    assert html =~ ~s|class="text muted">stderr|
    assert html =~ ~s|class="text primary">  ok|
    assert html =~ ~s|class="text primary">  warning|
    refute html =~ "tool-stream-stdout"
    refute html =~ "/tmp/app"
  end

  test "live compact tool has a single expand affordance" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test"},
        display: %Display{compact_limit: {:lines, 2}}
      )
      |> Block.append_stream(:stdout, "one\ntwo\nthree\nfour\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    html = render_component(&Tilde.Transport.Live.Tool.tool/1, block: tool)

    refute html =~ "more stdout lines"
    assert html =~ "… 2 more lines"
    assert html =~ "ctrl+o"
    assert html =~ "expand"
  end

  test "markdown facade uses configured backend" do
    with_application_env(:markdown_backend, TildeTest.MarkdownBackend, fn ->
      assert Tilde.Runtime.Markdown.backend() == TildeTest.MarkdownBackend
      assert Tilde.Runtime.Markdown.to_html("hello") == {:ok, "<p>fake hello</p>"}
    end)
  end

  test "markdown renderer uses MDEx for safe HTML" do
    assert {:ok, html} = Tilde.Runtime.Markdown.to_html("**bold** and `code`")
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<code>code</code>"

    assert {:ok, safe_html} = Tilde.Runtime.Markdown.to_html("<script>alert(1)</script>")
    refute safe_html =~ "<script>"

    assert {:ok, table_html} =
             Tilde.Runtime.Markdown.to_html(
               "| name | status |\n| --- | ---: |\n| LiveView | ok |"
             )

    assert table_html =~ "<table>"
    assert table_html =~ "<th>name</th>"
    assert table_html =~ "<td>LiveView</td>"
  end

  test "markdown renderer can complete streaming fragments with MDEx" do
    assert {:ok, bold_html} = Tilde.Runtime.Markdown.to_html("**Fol", streaming: true)
    assert bold_html =~ "<strong>Fol</strong>"

    assert {:ok, table_html} =
             Tilde.Runtime.Markdown.to_html(
               "| surface | renderer\n| --- | ---\n| web | LiveView",
               streaming: true
             )

    assert table_html =~ "<table>"
    assert table_html =~ "<td>LiveView</td>"

    assert {:ok, safe_html} =
             Tilde.Runtime.Markdown.to_html("<script>alert(1)</script>", streaming: true)

    refute safe_html =~ "<script>"
  end

  test "live message renders markdown source with MDEx" do
    block = Block.message("msg_1", :assistant, "**bold** and `code`")
    html = render_component(&Tilde.Transport.Live.Message.message/1, block: block)

    assert html =~ "markdown"
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<code>code</code>"
  end

  test "tui markdown tables render as ASCII grids from MDEx AST" do
    markdown = """
    Before

    | surface | renderer |
    | --- | ---: |
    | web | LiveView DOM |
    | ssh | semantic TUI |

    After
    """

    lines = Tilde.Renderer.TUI.Markdown.render_lines(markdown)

    assert "Before" in lines
    assert "┌─────────┬──────────────┐" in lines
    assert "│ surface │     renderer │" in lines
    assert "│ web     │ LiveView DOM │" in lines
    assert "│ ssh     │ semantic TUI │" in lines
    assert "└─────────┴──────────────┘" in lines
    assert "After" in lines
  end

  test "tui markdown thematic breaks render as three dimmed lines" do
    lines = Tilde.Renderer.TUI.Markdown.render_lines("Before\n\n---\n\nAfter", 8, ansi: false)

    assert lines == [
             "Before",
             "────────",
             "────────",
             "────────",
             "After"
           ]

    ansi_lines = Tilde.Renderer.TUI.Markdown.render_lines("---", 3, ansi: true)
    assert [_, _, _] = ansi_lines
    assert Enum.all?(ansi_lines, &String.contains?(&1, IO.ANSI.faint()))
  end

  test "live markdown thematic breaks use three dimmed lines" do
    block = Block.message("msg_1", :assistant, "Before\n\n---\n\nAfter")

    html = render_component(&Tilde.Transport.Live.Message.message/1, block: block)
    css = asset_css("components/markdown.css")

    assert html =~ "<hr"
    assert css =~ ".tilde .markdown hr"
    assert css =~ "height: 3lh"
    assert css =~ "color: var(--color-muted)"
    assert css =~ "0 2.5lh / 100% 1px no-repeat"
  end

  test "live markdown tables remain semantic HTML with terminal-like styling" do
    block =
      Block.message("msg_1", :assistant, "| name | status |\n| --- | --- |\n| LiveView | ok |")

    html = render_component(&Tilde.Transport.Live.Message.message/1, block: block)
    css = asset_css("components/markdown.css")

    assert html =~ "<table>"
    assert html =~ "<th>name</th>"
    assert html =~ "<td>LiveView</td>"
    assert css =~ ".tilde .markdown table"
    assert css =~ "padding: 0 var(--space-cell)"
    assert css =~ "border: 1px solid var(--color-border)"
  end

  test "live message renders semantic runs as inline HTML" do
    block =
      Block.message("msg_1", :assistant, "",
        runs: [
          Run.new("bold", [:bold]),
          Run.new(" "),
          Run.new("under", [:underline]),
          Run.new(" "),
          Run.new("code", [:code]),
          Run.new(" link", [], %{href: "https://example.test"})
        ]
      )

    html = render_component(&Tilde.Transport.Live.Message.message/1, block: block)

    assert html =~ "<strong>"
    assert html =~ "bold"
    assert html =~ "<u>"
    assert html =~ "under"
    assert html =~ "<code>"
    assert html =~ "code"
    assert html =~ "href=\"https://example.test\""
  end

  test "tui renderer uses algebra layout and IO.ANSI output" do
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

  test "tui renderer can render ANSI without clearing normal terminal scrollback" do
    rendered =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Tilde.Renderer.TUI.render_to_string(width: 40, clear?: false)

    refute rendered =~ IO.ANSI.clear()
    refute rendered =~ IO.ANSI.home()
    assert rendered =~ "# tilde"
    assert strip_ansi(rendered) =~ "> "
  end

  test "tui renderer clips full-frame output to terminal height" do
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
    refute rendered =~ "model: thinking…"
    assert String.ends_with?(rendered, "> ")
  end

  test "tui renderer can render without ANSI for snapshots" do
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
