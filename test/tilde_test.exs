defmodule TildeTest.MarkdownBackend do
  @behaviour Tilde.Markdown.Backend

  @impl true
  def to_html(markdown, _opts), do: {:ok, "<p>fake #{markdown}</p>"}
end

defmodule TildeTest.KeyProvider do
  @behaviour Tilde.SSH.KeyProvider

  @impl true
  def ensure_system_dir(path, _opts), do: {:ok, path}
end

defmodule TildeTest.ToolRenderer do
  @behaviour Tilde.ToolRenderer

  @impl true
  def call(block) do
    Tilde.ToolRenderer.call_view("custom",
      segments: [%{text: block.args.value, color: :success}],
      tags: ["demo"]
    )
  end

  @impl true
  def result(_block, _opts), do: Tilde.ToolRenderer.result_view(lines: ["custom result"])
end

defmodule TildeTest.LLMBackend do
  @behaviour Tilde.LLM.Backend

  @impl true
  def respond(session, _opts), do: {:ok, "echo: #{Tilde.LLM.latest_user_text(session)}"}
end

defmodule TildeTest.FailingLLMBackend do
  @behaviour Tilde.LLM.Backend

  @impl true
  def respond(_session, _opts), do: {:error, :boom}
end

defmodule TildeTest.StreamingLLMBackend do
  @behaviour Tilde.LLM.Backend

  @impl true
  def respond(_session, _opts), do: {:ok, "unused"}

  @impl true
  def stream(_session, _opts), do: [{:delta, "hel"}, {:delta, "lo"}, {:done, "hello"}]
end

defmodule TildeTest.ToolStreamingLLMBackend do
  @behaviour Tilde.LLM.Backend

  @impl true
  def respond(_session, _opts), do: {:ok, "unused"}

  @impl true
  def stream(_session, _opts) do
    [
      {:tool_started, "tool_utc", "utc_now", %{}},
      {:tool_done, "tool_utc", :success, %{utc_now: "2026-06-14T00:00:00Z"}},
      {:delta, "done"},
      {:done, "done"}
    ]
  end
end

defmodule TildeTest do
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest
  import Plug.Test

  alias Tilde.{
    Block,
    Choice,
    Display,
    Input,
    Renderer,
    Run,
    Session,
    Stream,
    ToolView,
    Transcript
  }

  doctest Tilde

  test "reduces message and tool events into semantic blocks" do
    events = [
      Tilde.user_message("Run tests", id: "evt_user"),
      Tilde.assistant_delta("I'll run ", id: "evt_assistant", block_id: "msg_assistant"),
      Tilde.assistant_delta("them.", id: "evt_assistant_2", block_id: "msg_assistant"),
      Tilde.tool_started("bash", %{command: "mix test"}, id: "evt_tool", tool_call_id: "tool_1"),
      Tilde.tool_stream("tool_1", :stdout, "Compiling...\n"),
      Tilde.tool_stream("tool_1", :stdout, "2 tests, 0 failures\n"),
      Tilde.tool_done("tool_1", :success, %{exit_code: 0})
    ]

    transcript = Tilde.transcript(events)

    assert [user, assistant, tool] = transcript.blocks
    assert user.role == :user
    assert user.source == "Run tests"
    assert assistant.source == "I'll run them."
    assert tool.kind == :tool
    assert tool.name == "bash"
    assert tool.status == :success
    assert [%Stream{kind: :stdout} = stdout] = tool.streams
    assert Stream.lines(stdout) == ["Compiling...", "2 tests, 0 failures"]
    assert tool.result == %{exit_code: 0}
  end

  test "tool view truncates compact output and ctrl-o display expands without mutating streams" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test"},
        display: %Display{compact_limit: {:lines, 2}}
      )
      |> Block.append_stream(:stdout, "one\ntwo\nthree\n")

    compact = ToolView.view(tool)
    expanded = tool |> Block.update_display(%{expanded?: true}) |> ToolView.view()

    assert compact.lines == ["one", "two"]
    assert [%{kind: :stdout, lines: ["one", "two"], hidden_lines: 1}] = compact.streams
    assert compact.hidden_lines == 1
    refute compact.expanded?

    assert expanded.lines == ["one", "two", "three"]
    assert [%{kind: :stdout, lines: ["one", "two", "three"], hidden_lines: 0}] = expanded.streams
    assert expanded.hidden_lines == 0
    assert expanded.expanded?
    assert tool.streams |> hd() |> Stream.text() == "one\ntwo\nthree\n"
  end

  test "runs represent styling without choosing a renderer" do
    run = Run.new("underlined", [:bold, :underline], %{href: "https://example.test"})

    assert run.text == "underlined"
    assert :bold in run.marks
    assert :underline in run.marks
    assert run.attrs.href == "https://example.test"
  end

  test "tool view preserves stream identity and metadata" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test", cwd: "/tmp/app"},
        display: %Display{compact_limit: {:lines, 2}},
        metadata: %{duration_ms: 42}
      )
      |> Block.append_stream(:stdout, "ok\n")
      |> Block.append_stream(:stderr, "warning\nmore\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    view = ToolView.view(tool)

    assert view.metadata_rows == [cwd: "/tmp/app", exit: "0", duration: "42ms"]

    assert [stdout, stderr] = view.streams
    assert stdout.kind == :stdout
    assert stdout.lines == ["ok"]
    assert stdout.hidden_lines == 0
    assert stderr.kind == :stderr
    assert stderr.lines == ["warning"]
    assert stderr.hidden_lines == 1
  end

  test "live tool renders per-stream output classes" do
    tool =
      Block.tool("tool_1", "bash", %{command: "mix test", cwd: "/tmp/app"},
        display: %Display{compact_limit: {:lines, 3}}
      )
      |> Block.append_stream(:stdout, "ok\n")
      |> Block.append_stream(:stderr, "warning\n")
      |> Block.finish_tool(:success, %{exit_code: 0})

    html = render_component(&Tilde.Live.Tool.tool/1, block: tool)

    assert html =~ "tilde-tool-stream-stdout"
    assert html =~ "tilde-tool-stream-stderr"
    assert html =~ "data-stream-kind=\"stderr\""
    assert html =~ "cwd"
    assert html =~ "/tmp/app"
    assert html =~ "exit"
    assert html =~ "0"
  end

  test "markdown facade uses configured backend" do
    with_application_env(:markdown_backend, TildeTest.MarkdownBackend, fn ->
      assert Tilde.Markdown.backend() == TildeTest.MarkdownBackend
      assert Tilde.Markdown.to_html("hello") == {:ok, "<p>fake hello</p>"}
    end)
  end

  test "markdown renderer uses MDEx for safe HTML" do
    assert {:ok, html} = Tilde.Markdown.to_html("**bold** and `code`")
    assert html =~ "<strong>bold</strong>"
    assert html =~ "<code>code</code>"

    assert {:ok, safe_html} = Tilde.Markdown.to_html("<script>alert(1)</script>")
    refute safe_html =~ "<script>"

    assert {:ok, table_html} =
             Tilde.Markdown.to_html("| name | status |\n| --- | ---: |\n| LiveView | ok |")

    assert table_html =~ "<table>"
    assert table_html =~ "<th>name</th>"
    assert table_html =~ "<td>LiveView</td>"
  end

  test "markdown renderer can complete streaming fragments with MDEx" do
    assert {:ok, bold_html} = Tilde.Markdown.to_html("**Fol", streaming: true)
    assert bold_html =~ "<strong>Fol</strong>"

    assert {:ok, table_html} =
             Tilde.Markdown.to_html("| surface | renderer\n| --- | ---\n| web | LiveView",
               streaming: true
             )

    assert table_html =~ "<table>"
    assert table_html =~ "<td>LiveView</td>"

    assert {:ok, safe_html} = Tilde.Markdown.to_html("<script>alert(1)</script>", streaming: true)
    refute safe_html =~ "<script>"
  end

  test "live message renders markdown source with MDEx" do
    block = Block.message("msg_1", :assistant, "**bold** and `code`")
    html = render_component(&Tilde.Live.Message.message/1, block: block)

    assert html =~ "tilde-markdown"
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

    lines = Tilde.TUI.Markdown.render_lines(markdown)

    assert "Before" in lines
    assert "┌─────────┬──────────────┐" in lines
    assert "│ surface │     renderer │" in lines
    assert "│ web     │ LiveView DOM │" in lines
    assert "│ ssh     │ semantic TUI │" in lines
    assert "└─────────┴──────────────┘" in lines
    assert "After" in lines
  end

  test "live markdown tables remain semantic HTML with terminal-like styling" do
    block =
      Block.message("msg_1", :assistant, "| name | status |\n| --- | --- |\n| LiveView | ok |")

    html = render_component(&Tilde.Live.Message.message/1, block: block)
    css = Tilde.Live.Styles.css()

    assert html =~ "<table>"
    assert html =~ "<th>name</th>"
    assert html =~ "<td>LiveView</td>"
    assert css =~ ".tilde-markdown table"
    assert css =~ "padding: 0 var(--tilde-cell)"
    assert css =~ "border: 1px solid var(--tilde-line)"
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

    html = render_component(&Tilde.Live.Message.message/1, block: block)

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

    rendered = Tilde.TUI.Renderer.render_to_string(session, width: 60)
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
      |> Tilde.TUI.Renderer.render_to_string(width: 40, clear?: false)

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
        Tilde.user_message("three", id: "evt_three")
      ])
      |> Session.put_status("model", "thinking…")

    rendered =
      session |> Tilde.TUI.Renderer.render_to_string(width: 40, height: 6) |> strip_ansi()

    refute rendered =~ "# tilde"
    refute rendered =~ "one"
    assert rendered =~ "three"
    assert rendered =~ "model: thinking…\r\n\r\n> "
    assert String.ends_with?(rendered, "> ")
  end

  test "tui renderer can render without ANSI for snapshots" do
    rendered =
      Tilde.session(id: "session_1")
      |> Session.append_event(Tilde.user_message("hello", id: "evt_user"))
      |> Tilde.TUI.Renderer.render_to_string(width: 40, ansi: false)

    refute rendered =~ IO.ANSI.clear()
    assert rendered =~ "# tilde"
    assert rendered =~ "user"
    assert rendered =~ "hello"
    assert rendered =~ "> ▌"
  end

  test "ssh keys facade uses configured provider" do
    with_application_env(:ssh_key_provider, TildeTest.KeyProvider, fn ->
      assert Tilde.SSH.Keys.provider() == TildeTest.KeyProvider
      assert Tilde.SSH.Keys.ensure_system_dir("/tmp/fake") == {:ok, "/tmp/fake"}
    end)
  end

  test "ssh key generation uses Erlang public_key PEM host keys" do
    dir = Path.join(System.tmp_dir!(), "tilde-ssh-test-#{System.unique_integer([:positive])}")

    assert {:ok, ^dir} = Tilde.SSH.Keys.ensure_system_dir(dir)
    key_path = Path.join(dir, "ssh_host_rsa_key")
    assert File.exists?(key_path)

    assert [{:RSAPrivateKey, _key, :not_encrypted}] =
             key_path |> File.read!() |> :public_key.pem_decode()

    File.rm_rf!(dir)
  end

  test "command suggestions are semantic widgets and TUI tab completes them" do
    assert %Tilde.Suggest{title: "commands", items: items} = Tilde.Command.suggestions("/co")
    assert Enum.map(items, & &1.label) == ["/compact"]
    assert Tilde.Command.completion("/co") == "/compact"

    session = Session.append_event(Tilde.session(), Tilde.input_changed("/co"))
    assert [suggest_widget] = Session.widgets(session, :above_input)
    assert %Tilde.Suggest{} = suggest_widget.content

    html = render_component(&Tilde.Live.Console.console/1, session: session)
    assert html =~ "tilde-suggest"
    assert html =~ "/compact"
    assert html =~ "phx-click=\"tilde:complete_input\""

    assert {:cont, completed} = Tilde.TUI.Controller.apply_key(session, :tab)
    assert completed.input.value == "/compact"
  end

  test "slash commands parse and apply semantic effects" do
    assert {:ok, %Tilde.Command{name: "help"}} = Tilde.Command.parse("/help")

    assert {:ok, %Tilde.Command{name: "new", args: "My Demo"}} =
             Tilde.Command.parse("/new My Demo")

    assert Tilde.Command.parse("not a command") == :error
    assert Tilde.Command.new_session_id("My Demo") == "my-demo"

    session = Tilde.session(id: "cmd")
    effects = Tilde.Command.run(%Tilde.Command{name: "session"}, session, [])
    updated = Tilde.Command.apply_effects(session, effects)

    assert [%Block{role: :assistant, source: source}] = updated.transcript.blocks
    assert source =~ "Session: cmd"
  end

  test "session server handles slash commands without invoking the LLM" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.StreamingLLMBackend, fn ->
        name = :"tilde_session_server_command_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.SessionServer.start_link(
                   name: name,
                   session: Tilde.session(id: "cmd_test")
                 )

        assert %Session{} = Tilde.SessionServer.subscribe(name)

        updated = Tilde.SessionServer.append_event(name, Tilde.input_submitted("/help"))

        assert [%Block{role: :user, source: "/help"}, %Block{role: :assistant, source: source}] =
                 updated.transcript.blocks

        assert source =~ "/new [name]"

        refute_receive {:tilde_session_updated, "cmd_test",
                        %Session{statuses: %{"model" => "thinking…"}}},
                       50

        GenServer.stop(pid)
      end)
    end)
  end

  test "session registry names isolate session servers without dynamic atoms" do
    with_application_env(:llm_enabled, false, fn ->
      assert Tilde.SessionRegistry.normalize_id("My Session!!") == "my-session"
      assert {:ok, _pid} = Tilde.SessionRegistry.ensure_started()

      left = Tilde.SessionRegistry.via("left-#{System.unique_integer([:positive])}")
      right = Tilde.SessionRegistry.via("right-#{System.unique_integer([:positive])}")

      assert {:ok, left_pid} =
               Tilde.SessionServer.ensure_started(left, session: Tilde.session(id: "left"))

      assert {:ok, right_pid} =
               Tilde.SessionServer.ensure_started(right, session: Tilde.session(id: "right"))

      Tilde.SessionServer.append_event(left, Tilde.input_submitted("left only"))
      Tilde.SessionServer.append_event(right, Tilde.input_submitted("right only"))

      assert [%Block{source: "left only"}] =
               Tilde.SessionServer.get_session(left).transcript.blocks

      assert [%Block{source: "right only"}] =
               Tilde.SessionServer.get_session(right).transcript.blocks

      GenServer.stop(left_pid)
      GenServer.stop(right_pid)
    end)
  end

  test "session server mirrors one semantic session to subscribers" do
    name = :"tilde_session_server_test_#{System.unique_integer([:positive])}"
    session = Tilde.session(id: "mirror_test")

    assert {:ok, pid} = Tilde.SessionServer.start_link(name: name, session: session)
    assert %Session{id: "mirror_test"} = Tilde.SessionServer.subscribe(name)

    updated = Tilde.SessionServer.append_event(name, Tilde.input_submitted("from ssh"))

    assert [%Block{role: :user, source: "from ssh"}] = updated.transcript.blocks
    assert_receive {:tilde_session_updated, "mirror_test", ^updated}

    GenServer.stop(pid)
  end

  test "session server leaves submissions alone when LLM responses are disabled" do
    with_application_env(:llm_enabled, false, fn ->
      name = :"tilde_session_server_llm_disabled_test_#{System.unique_integer([:positive])}"

      assert {:ok, pid} =
               Tilde.SessionServer.start_link(
                 name: name,
                 session: Tilde.session(id: "llm_disabled")
               )

      assert %Session{} = Tilde.SessionServer.subscribe(name)

      updated = Tilde.SessionServer.append_event(name, Tilde.input_submitted("hello"))

      assert [%Block{role: :user, source: "hello"}] = updated.transcript.blocks
      assert_receive {:tilde_session_updated, "llm_disabled", ^updated}

      refute_receive {:tilde_session_updated, "llm_disabled",
                      %Session{transcript: %{blocks: [_, _]}}},
                     50

      GenServer.stop(pid)
    end)
  end

  test "session server appends async assistant replies through configured LLM backend" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.LLMBackend, fn ->
        name = :"tilde_session_server_llm_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.SessionServer.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_test")
                 )

        assert %Session{} = Tilde.SessionServer.subscribe(name)

        Tilde.SessionServer.append_event(name, Tilde.input_submitted("hello"))

        assert_receive {:tilde_session_updated, "llm_test",
                        %Session{transcript: %{blocks: [_user]}}}

        assert_receive {:tilde_session_updated, "llm_test",
                        %Session{statuses: %{"model" => "thinking…"}}}

        assert_receive {:tilde_session_updated, "llm_test",
                        %Session{
                          statuses: statuses,
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{role: :assistant, source: "echo: hello"}
                            ]
                          }
                        }}

        refute Map.has_key?(statuses, "model")

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server streams LLM deltas into one assistant block" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.StreamingLLMBackend, fn ->
        name = :"tilde_session_server_llm_stream_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.SessionServer.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_stream")
                 )

        assert %Session{} = Tilde.SessionServer.subscribe(name)

        Tilde.SessionServer.append_event(name, Tilde.input_submitted("hello"))

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{statuses: %{"model" => "thinking…"}}}

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{
                          transcript: %{
                            blocks: [%Block{role: :user}, %Block{role: :assistant, source: "hel"}]
                          }
                        }}

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{
                          statuses: %{"model" => "thinking…"},
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{role: :assistant, source: "hello"}
                            ]
                          }
                        }}

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{
                          statuses: statuses,
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{role: :assistant, source: "hello"}
                            ]
                          }
                        }}

        refute Map.has_key?(statuses, "model")
        GenServer.stop(pid)
      end)
    end)
  end

  test "session server renders streamed LLM tool events as semantic tool blocks" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.ToolStreamingLLMBackend, fn ->
        name = :"tilde_session_server_llm_tool_stream_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.SessionServer.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_tool_stream")
                 )

        assert %Session{} = Tilde.SessionServer.subscribe(name)

        Tilde.SessionServer.append_event(name, Tilde.input_submitted("what time is it?"))

        assert_receive {:tilde_session_updated, "llm_tool_stream",
                        %Session{
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{kind: :tool, id: "tool_utc", name: "utc_now"}
                            ]
                          }
                        }}

        assert_receive {:tilde_session_updated, "llm_tool_stream",
                        %Session{
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{
                                kind: :tool,
                                status: :success,
                                result: %{utc_now: "2026-06-14T00:00:00Z"}
                              },
                              %Block{role: :assistant, source: "done"}
                            ]
                          }
                        }}

        GenServer.stop(pid)
      end)
    end)
  end

  test "utc_now tool returns an ISO 8601 timestamp" do
    assert {:ok, %{utc_now: timestamp}} = Tilde.Tools.UtcNow.run(%{}, %{})
    assert {:ok, _datetime, 0} = DateTime.from_iso8601(timestamp)
  end

  test "session server rate limits public demo LLM submissions" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.StreamingLLMBackend, fn ->
        rate_limit = [
          scope: :"test_#{System.unique_integer([:positive])}",
          scale: :timer.minutes(1),
          limit: 0
        ]

        with_application_env(:llm_rate_limit, rate_limit, fn ->
          assert {:ok, _pid} = Tilde.RateLimit.ensure_started()
          name = :"tilde_session_server_llm_rate_limit_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.SessionServer.start_link(
                     name: name,
                     session: Tilde.session(id: "llm_rate_limit")
                   )

          assert %Session{} = Tilde.SessionServer.subscribe(name)

          Tilde.SessionServer.append_event(name, Tilde.input_submitted("hello"))

          assert_receive {:tilde_session_updated, "llm_rate_limit",
                          %Session{
                            transcript: %{
                              blocks: [
                                %Block{role: :user},
                                %Block{
                                  role: :assistant,
                                  source: "The public demo is busy. Please try again in " <> _rest
                                }
                              ]
                            }
                          }}

          refute_receive {:tilde_session_updated, "llm_rate_limit",
                          %Session{statuses: %{"model" => "thinking…"}}},
                         50

          GenServer.stop(pid)
        end)
      end)
    end)
  end

  test "session server turns LLM backend failures into public assistant messages" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.FailingLLMBackend, fn ->
        name = :"tilde_session_server_llm_failure_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.SessionServer.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_failure")
                 )

        assert %Session{} = Tilde.SessionServer.subscribe(name)

        Tilde.SessionServer.append_event(name, Tilde.input_submitted("hello"))

        assert_receive {:tilde_session_updated, "llm_failure",
                        %Session{transcript: %{blocks: [_user]}}}

        assert_receive {:tilde_session_updated, "llm_failure",
                        %Session{statuses: %{"model" => "thinking…"}}}

        assert_receive {:tilde_session_updated, "llm_failure",
                        %Session{
                          statuses: statuses,
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{
                                role: :assistant,
                                source: "The model is unavailable right now. Please try again."
                              }
                            ]
                          }
                        }}

        refute Map.has_key?(statuses, "model")

        GenServer.stop(pid)
      end)
    end)
  end

  test "jido LLM backend reports a missing OpenRouter key before calling the runtime" do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.delete_env("OPENROUTER_API_KEY")

    assert Tilde.LLM.Jido.respond(Tilde.session()) == {:error, :missing_openrouter_api_key}

    if previous, do: System.put_env("OPENROUTER_API_KEY", previous)
  end

  test "session server applies TUI keys for mirrored renderers" do
    name = :"tilde_session_server_keys_test_#{System.unique_integer([:positive])}"
    assert {:ok, pid} = Tilde.SessionServer.start_link(name: name, session: Tilde.session())

    assert {:cont, session} = Tilde.SessionServer.apply_key(name, {:text, "h"})
    assert session.input.value == "h"

    assert {:cont, submitted} = Tilde.SessionServer.apply_key(name, :enter)
    assert submitted.input.value == ""
    assert [%Block{role: :user, source: "h"}] = submitted.transcript.blocks

    GenServer.stop(pid)
  end

  test "ssh demo daemon starts with generated host keys" do
    dir =
      Path.join(System.tmp_dir!(), "tilde-ssh-daemon-test-#{System.unique_integer([:positive])}")

    assert {:ok, pid} = Tilde.SSH.Demo.start_link(port: 0, system_dir: dir)
    assert is_pid(Tilde.SSH.Demo.daemon_ref(pid))
    GenServer.stop(pid)
    File.rm_rf!(dir)
  end

  @tag timeout: 45_000
  test "ssh sessions are private by default and attach only when explicit" do
    skip_unless_executable("ssh")
    skip_unless_executable("setsid")

    with_application_env(:llm_enabled, false, fn ->
      dir =
        Path.join(
          System.tmp_dir!(),
          "tilde-ssh-isolation-test-#{System.unique_integer([:positive])}"
        )

      askpass = Path.join(dir, "askpass.sh")
      File.mkdir_p!(dir)
      File.write!(askpass, "#!/bin/sh\necho tilde\n")
      File.chmod!(askpass, 0o700)

      {:ok, pid} = Tilde.SSH.Demo.start_link(port: 0, system_dir: dir, password: "tilde")
      [port: port] = :ssh.daemon_info(Tilde.SSH.Demo.daemon_ref(pid), [:port])

      try do
        stamp = System.unique_integer([:positive])
        private_a = "AAA_PRIVATE_#{stamp}"
        private_b = "BBB_PRIVATE_#{stamp}"

        task_a = ssh_script(port, askpass, "printf '#{private_a}'; sleep 2")
        task_b = ssh_script(port, askpass, "printf '#{private_b}'; sleep 2")

        output_a = Task.await(task_a, 15_000)
        output_b = Task.await(task_b, 15_000)

        assert output_a =~ private_a
        assert output_b =~ private_b
        refute output_a =~ private_b
        refute output_b =~ private_a

        attached = "ssh-smoke-#{stamp}"
        attached_a = "AAA_ATTACHED_#{stamp}"
        attached_b = "BBB_ATTACHED_#{stamp}"

        attach_a =
          ssh_script(
            port,
            askpass,
            "printf '/attach #{attached}\\r'; sleep 1; printf '#{attached_a}'; sleep 1; printf '\\r'; sleep 2"
          )

        attach_b =
          ssh_script(
            port,
            askpass,
            "printf '/attach #{attached}\\r'; sleep 1; printf '#{attached_b}'; sleep 4"
          )

        attached_output_a = Task.await(attach_a, 15_000)
        attached_output_b = Task.await(attach_b, 15_000)

        assert attached_output_a =~ "attached session: #{attached}"
        assert attached_output_b =~ "attached session: #{attached}"
        assert attached_output_b =~ attached_a
        refute attached_output_a =~ attached_b
        assert last_prompt(attached_output_b) =~ attached_b
        refute last_prompt(attached_output_b) =~ attached_a
      after
        GenServer.stop(pid)
        File.rm_rf!(dir)
      end
    end)
  end

  test "semantic status events update and clear session statuses" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.status_changed("model", "thinking…"))

    assert session.statuses["model"] == "thinking…"
    assert session.transcript.statuses["model"] == "thinking…"

    cleared = Session.append_event(session, Tilde.status_changed("model", nil))

    refute Map.has_key?(cleared.statuses, "model")
    refute Map.has_key?(cleared.transcript.statuses, "model")
  end

  test "semantic input events update input state and submit transcript messages" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.input_changed("hello", metadata: %{cursor: 5}))

    assert %Input{value: "hello", cursor: 5} = session.input
    assert session.transcript.blocks == []

    submitted = Session.append_event(session, Tilde.input_submitted("hello"))

    assert submitted.input.value == ""
    assert [%Block{role: :user, source: "hello"}] = submitted.transcript.blocks
  end

  test "tui controller edits and submits semantic input" do
    assert {:cont, session} = Tilde.TUI.Controller.apply_key(Tilde.session(), {:text, "h"})
    assert {:cont, session} = Tilde.TUI.Controller.apply_key(session, {:text, "i"})
    assert session.input.value == "hi"

    assert {:cont, session} = Tilde.TUI.Controller.apply_key(session, :backspace)
    assert session.input.value == "h"

    assert {:cont, session} = Tilde.TUI.Controller.apply_key(session, {:text, "!"})
    assert {:cont, submitted} = Tilde.TUI.Controller.apply_key(session, :enter)

    assert submitted.input.value == ""
    assert [%Block{role: :user, source: "h!"}] = submitted.transcript.blocks
  end

  test "tui controller applies keys to semantic session" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    assert {:cont, toggled} = Tilde.TUI.Controller.apply_key(session, :toggle_expand)
    assert [%Block{display: %{expanded?: true}}] = toggled.transcript.blocks
    assert {:halt, ^toggled} = Tilde.TUI.Controller.apply_key(toggled, :quit)
  end

  test "ssh channel initializes semantic demo state" do
    assert {:ok, state} = Tilde.SSH.Channel.init([[width: 72, height: 24]])
    assert state.width == 72
    assert state.height == 24
    assert %Session{} = state.session
  end

  test "ssh shell applies tui keys to semantic session" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    assert {:cont, toggled} = Tilde.SSH.Shell.apply_key(session, :toggle_expand)
    assert [%Block{display: %{expanded?: true}}] = toggled.transcript.blocks
    assert {:halt, ^toggled} = Tilde.SSH.Shell.apply_key(toggled, :quit)
  end

  test "tui key decoder maps terminal bytes to semantic actions" do
    assert Tilde.TUI.Keys.decode(<<15>>) == :toggle_expand
    assert Tilde.TUI.Keys.decode("q") == :quit
    assert Tilde.TUI.Keys.decode("r") == :redraw
    assert Tilde.TUI.Keys.decode("\t") == :tab
    assert Tilde.TUI.Keys.decode("\e[Z") == :backtab
    assert Tilde.TUI.Keys.decode("\r") == :enter
    assert Tilde.TUI.Keys.decode(<<127>>) == :backspace
    assert Tilde.TUI.Keys.decode(<<27>>) == :cancel
    assert Tilde.TUI.Keys.decode(<<3>>) == :interrupt
    assert Tilde.TUI.Keys.decode("a") == {:text, "a"}

    assert Tilde.TUI.Keys.decode_many("q\r") == [:quit]
    assert Tilde.TUI.Keys.decode_many("r\r") == [:redraw]

    assert Tilde.TUI.Keys.decode_many("hello\r") == [
             {:text, "h"},
             {:text, "e"},
             {:text, "l"},
             {:text, "l"},
             {:text, "o"},
             :enter
           ]
  end

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
                 Tilde.SessionServer.start_link(
                   name: name,
                   session: Tilde.session(id: "trim_test")
                 )

        Tilde.SessionServer.append_event(name, Tilde.input_submitted("one"))
        Tilde.SessionServer.append_event(name, Tilde.assistant_done("two"))
        updated = Tilde.SessionServer.append_event(name, Tilde.input_submitted("three"))

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
    require Tilde.Template.Live
    require Tilde.Template.TUI

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

    live = source |> Tilde.Template.Live.render!() |> rendered_to_string()
    tui = Tilde.Template.TUI.render!(source, 50)

    assert live =~ "tilde-view-text-title"
    assert live =~ "tilde-view-text-accent"
    assert strip_ansi(tui) =~ "bash mix test"
    assert strip_ansi(tui) =~ "ok"
    assert tui =~ IO.ANSI.bright()
  end

  test "Tilde semantic HEEx templates support assigns, message cells, and markdown" do
    require Tilde.Template
    require Tilde.Template.Live
    require Tilde.Template.TUI

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
      |> Tilde.Template.Live.render!(assigns: %{role: "user", name: "Ada"})
      |> rendered_to_string()

    tui = Tilde.Template.TUI.render!(source, 50, assigns: %{role: "user", name: "Ada"})

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
    cell = Tilde.View.Builder.block(block)

    assert cell.attrs.template == :source
    live = render_component(&Tilde.Live.ViewRenderer.cell/1, cell: cell)
    live_text = strip_html(live)
    tui = cell |> Tilde.TUI.ViewRenderer.render(60, ansi: true) |> strip_ansi()

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

  test "tool renderer registry customizes semantic call and result views" do
    with_application_env(:tool_renderers, %{"custom_tool" => TildeTest.ToolRenderer}, fn ->
      session =
        Tilde.session()
        |> Session.append_events([
          Tilde.tool_started("custom_tool", %{value: "ok"}, tool_call_id: "tool_1"),
          Tilde.tool_done("tool_1")
        ])

      html = render_component(&Tilde.Live.Console.console/1, session: session)
      tui = session |> Tilde.TUI.Renderer.render() |> Enum.join() |> strip_ansi()

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

    html = render_component(&Tilde.Live.Console.console/1, session: session)
    tui = session |> Tilde.TUI.Renderer.render() |> Enum.join()

    assert html =~ "bash"
    assert html =~ "mix test"
    assert html =~ "Waiting…"
    refute html =~ "tilde-tool-status"
    assert tui =~ "Waiting…"
  end

  test "demo session renders a complete dogfood console" do
    session = Tilde.Live.Demo.demo_session()
    html = render_component(&Tilde.Live.Console.console/1, session: session)

    tool_cell =
      session.transcript.blocks |> Enum.find(&(&1.kind == :tool)) |> Tilde.View.Builder.block()

    assert tool_cell.attrs.template == :source
    assert html =~ "Build a pi-like console"
    assert html =~ "tool_demo_tests"
    refute html =~ "cwd ~/Development/elixir-vibe/tilde"
    refute html =~ "exit 0"
    assert html =~ "tilde-tool-success"
    refute html =~ "tilde-tool-status"
    refute html =~ "✓"
    assert html =~ "tilde-shortcut-key"
    assert html =~ "ctrl+o"
    assert html =~ "expand"
    assert html =~ "Apply the generated patch?"
    refute html =~ "background: no running jobs"
  end

  test "web demo requires password session" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :get
        |> conn("/tilde")
        |> init_test_session(%{})
        |> Tilde.Live.DemoRouter.call([])

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
        |> Tilde.Live.DemoAuth.create(%{
          "password" => "secret",
          "return_to" => "/tilde/auth-smoke"
        })

      assert conn.status == 302
      assert Plug.Conn.get_session(conn, :tilde_demo_authenticated) == true
      assert Plug.Conn.get_resp_header(conn, "location") == ["/tilde/auth-smoke"]
    end)
  end

  test "web demo login rejects wrong password" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Live.DemoAuth.create(%{"password" => "wrong", "return_to" => "/tilde"})

      assert conn.status == 401
      refute Plug.Conn.get_session(conn, :tilde_demo_authenticated)
      assert conn.resp_body =~ "Incorrect password"
    end)
  end

  test "live hooks expose ctrl-o focused block expansion JavaScript" do
    js = Tilde.Live.Hooks.js()

    assert js =~ "TildeConsole"
    assert js =~ "ctrlKey"
    assert js =~ "key === \"tab\""
    assert js =~ "tilde:complete_input"
    assert js =~ "tilde:toggle_expand"
    assert js =~ "[data-block-id]"
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

    html = render_component(&Tilde.Live.Console.console/1, session: session, input: "next")

    assert html =~ "phx-hook=\"TildeConsole\""
    assert html =~ "tilde-console"
    assert html =~ "Run tests"
    assert html =~ "bash"
    assert html =~ "mix test"
    assert html =~ "ok"
    assert html =~ "server running"
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

  defp with_application_env(key, value, fun) do
    previous = Application.get_env(:tilde, key)
    Application.put_env(:tilde, key, value)

    result = fun.()
    restore_application_env(key, previous)
    result
  end

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
  end

  defp strip_html(text), do: Regex.replace(~r/<[^>]+>/, text, "")

  defp skip_unless_executable(executable) do
    unless System.find_executable(executable) do
      flunk("#{executable} executable is required for SSH integration coverage")
    end
  end

  defp ssh_script(port, askpass, producer_script) do
    Task.async(fn ->
      command = """
      (#{producer_script}) | timeout 10 setsid env \
        SSH_ASKPASS="$TILDE_ASKPASS" \
        SSH_ASKPASS_REQUIRE=force \
        DISPLAY=:0 \
        ssh tilde@localhost \
          -p "$TILDE_PORT" \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o PreferredAuthentications=password \
          -o PubkeyAuthentication=no
      """

      {output, _status} =
        System.cmd("bash", ["-lc", command],
          env: [{"TILDE_PORT", to_string(port)}, {"TILDE_ASKPASS", askpass}],
          stderr_to_stdout: true
        )

      strip_ansi(output)
    end)
  end

  defp last_prompt(output) do
    output
    |> String.split(["\r", "\n"], trim: true)
    |> Enum.filter(&String.starts_with?(&1, ">"))
    |> List.last()
    |> Kernel.||("")
  end

  defp restore_application_env(key, nil), do: Application.delete_env(:tilde, key)
  defp restore_application_env(key, previous), do: Application.put_env(:tilde, key, previous)
end
