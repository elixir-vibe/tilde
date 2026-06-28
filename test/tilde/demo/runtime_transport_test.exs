defmodule Tilde.DemoRuntimeTransportTest do
  use TildeTest.Case

  test "jido LLM backend reports a missing OpenRouter key before calling the runtime" do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.delete_env("OPENROUTER_API_KEY")

    assert [
             %Jido.AI.Runtime.Event{
               kind: :request_failed,
               data: %{error: :missing_openrouter_api_key}
             }
           ] =
             Enum.to_list(Tilde.Runtime.LLM.Provider.Jido.stream(Tilde.session()))

    if previous, do: System.put_env("OPENROUTER_API_KEY", previous)
  end

  test "demo environment loads OpenRouter key from dotenv files" do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.delete_env("OPENROUTER_API_KEY")

    dir = Path.join(System.tmp_dir!(), "tilde-env-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, ".env"), "OPENROUTER_API_KEY=from-dotenv\n")

    File.cd!(dir, fn -> assert Tilde.Demo.Environment.load() == :ok end)
    assert System.get_env("OPENROUTER_API_KEY") == "from-dotenv"

    File.rm_rf!(dir)
    restore_system_env("OPENROUTER_API_KEY", previous)
  end

  test "session server applies TUI keys for mirrored renderers" do
    name = :"tilde_session_server_keys_test_#{System.unique_integer([:positive])}"
    assert {:ok, pid} = Tilde.Session.Server.start_link(name: name, session: Tilde.session())

    assert {:cont, session} = Tilde.Session.Server.apply_key(name, {:text, "h"})
    assert session.input.value == "h"

    assert {:cont, submitted} = Tilde.Session.Server.apply_key(name, :enter)
    assert submitted.input.value == ""
    assert [%Block{role: :user, source: "h"}] = submitted.transcript.blocks

    GenServer.stop(pid)
  end

  test "ssh demo daemon starts with generated host keys" do
    dir =
      Path.join(System.tmp_dir!(), "tilde-ssh-daemon-test-#{System.unique_integer([:positive])}")

    assert {:ok, pid} = Tilde.Transport.SSH.Demo.start_link(port: 0, system_dir: dir)
    assert is_pid(Tilde.Transport.SSH.Demo.daemon_ref(pid))
    GenServer.stop(pid)
    File.rm_rf!(dir)
  end

  test "ssh session servers are private until explicitly shared" do
    with_application_env(:llm_enabled, false, fn ->
      {:ok, _pid} = Tilde.Session.Registry.ensure_started()
      stamp = System.unique_integer([:positive])

      private_a = Tilde.Session.Registry.via("ssh-private-a-#{stamp}")
      private_b = Tilde.Session.Registry.via("ssh-private-b-#{stamp}")
      shared = Tilde.Session.Registry.via("ssh-shared-#{stamp}")

      {:ok, private_a_pid} =
        Tilde.Session.Server.ensure_started(private_a,
          session: Tilde.Demo.Live.demo_session(id: "ssh-private-a-#{stamp}")
        )

      {:ok, private_b_pid} =
        Tilde.Session.Server.ensure_started(private_b,
          session: Tilde.Demo.Live.demo_session(id: "ssh-private-b-#{stamp}")
        )

      {:ok, shared_pid} =
        Tilde.Session.Server.ensure_started(shared,
          session: Tilde.Demo.Live.demo_session(id: "ssh-shared-#{stamp}")
        )

      on_exit(fn ->
        Enum.each([private_a_pid, private_b_pid, shared_pid], fn pid ->
          if Process.alive?(pid), do: GenServer.stop(pid)
        end)
      end)

      a_marker = "AAA_PRIVATE_#{stamp}"
      b_marker = "BBB_PRIVATE_#{stamp}"

      Tilde.Session.Server.update_session(
        private_a,
        &Session.append_event(&1, Tilde.input_submitted(a_marker))
      )

      Tilde.Session.Server.update_session(
        private_b,
        &Session.append_event(&1, Tilde.input_submitted(b_marker))
      )

      private_a_session = Tilde.Session.Server.get_session(private_a)
      private_b_session = Tilde.Session.Server.get_session(private_b)

      assert latest_user_sources(private_a_session) == [a_marker]
      assert latest_user_sources(private_b_session) == [b_marker]
      refute b_marker in latest_user_sources(private_a_session)
      refute a_marker in latest_user_sources(private_b_session)

      shared_a = "AAA_ATTACHED_#{stamp}"
      shared_b_prompt = "BBB_ATTACHED_PROMPT_#{stamp}"

      Tilde.Session.Server.update_session(
        shared,
        &Session.append_event(&1, Tilde.input_submitted(shared_a))
      )

      shared_for_a = Tilde.Session.Server.get_session(shared)

      shared_for_b =
        shared
        |> Tilde.Session.Server.get_session()
        |> Session.put_input(Input.put_value(%Input{}, shared_b_prompt))

      assert shared_a in latest_user_sources(shared_for_a)
      assert shared_a in latest_user_sources(shared_for_b)
      assert shared_for_b.input.value == shared_b_prompt
      assert Tilde.Session.Server.get_session(shared).input.value == ""
    end)
  end

  test "semantic status events update and clear session statuses" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.status_changed("runtime", "busy"))

    assert session.statuses["runtime"] == "busy"
    assert session.transcript.statuses["runtime"] == "busy"

    cleared = Session.append_event(session, Tilde.status_changed("runtime", nil))

    refute Map.has_key?(cleared.statuses, "runtime")
    refute Map.has_key?(cleared.transcript.statuses, "runtime")
  end

  test "assistant lifecycle events are strict session state, not generic statuses" do
    session =
      Tilde.session()
      |> Session.append_event(Tilde.assistant_turn_started(block_id: "msg_assistant_1"))

    assert_assistant_phase(session, :waiting)
    assert_assistant_waiting(session)
    assert session.assistant.block_id == "msg_assistant_1"
    refute Map.has_key?(session.statuses, "model")
    refute Map.has_key?(session.transcript.statuses, "model")

    streaming =
      Session.append_event(session, Tilde.assistant_delta("hello", block_id: "msg_assistant_1"))

    assert_assistant_phase(streaming, :streaming)
    refute_assistant_waiting(streaming)
    assert_assistant_active(streaming)

    done =
      Session.append_event(streaming, Tilde.assistant_turn_finished(block_id: "msg_assistant_1"))

    assert_assistant_phase(done, :done)
    refute_assistant_active(done)
  end

  test "assistant lifecycle tracks tool, error, and cancelled phases" do
    tooling =
      Tilde.session()
      |> Session.append_event(Tilde.assistant_turn_started(block_id: "msg_assistant_1"))
      |> Session.append_event(Tilde.tool_started("utc_now", %{}, tool_call_id: "tool_1"))

    assert_assistant_phase(tooling, :tooling)
    assert_assistant_active(tooling)

    failed = Session.append_event(tooling, Tilde.assistant_turn_error(:boom))

    assert_assistant_phase(failed, :error)
    refute_assistant_active(failed)
    assert failed.assistant.error == :boom

    cancelled =
      Tilde.session()
      |> Session.append_event(Tilde.assistant_turn_started(block_id: "msg_assistant_2"))
      |> Session.append_event(Tilde.assistant_turn_cancelled())

    assert_assistant_phase(cancelled, :cancelled)
    refute_assistant_active(cancelled)
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
    assert {:cont, session} = Tilde.Core.Controller.apply_key(Tilde.session(), {:text, "h"})
    assert {:cont, session} = Tilde.Core.Controller.apply_key(session, {:text, "i"})
    assert session.input.value == "hi"

    assert {:cont, session} = Tilde.Core.Controller.apply_key(session, :backspace)
    assert session.input.value == "h"

    assert {:cont, session} = Tilde.Core.Controller.apply_key(session, {:text, "!"})
    assert {:cont, submitted} = Tilde.Core.Controller.apply_key(session, :enter)

    assert submitted.input.value == ""
    assert [%Block{role: :user, source: "h!"}] = submitted.transcript.blocks
  end

  test "tui controller applies keys to semantic session" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    assert {:cont, toggled} = Tilde.Core.Controller.apply_key(session, :toggle_expand)
    assert [%Block{display: %{expanded?: true}}] = toggled.transcript.blocks
    assert {:halt, ^toggled} = Tilde.Core.Controller.apply_key(toggled, :quit)
  end

  test "ssh channel initializes semantic demo state" do
    assert {:ok, state} = Tilde.Transport.SSH.Channel.init([[width: 72, height: 24]])
    assert state.width == 72
    assert state.height == 24
    assert %Session{} = state.session
  end

  test "ssh rendering shows compaction blocks" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.context_compacted("## Context Compaction\n\nSummary",
          metadata: %{tokens_before: 1234, first_kept_block_id: "msg_1"}
        )
      )

    rendered =
      session
      |> Tilde.Transport.SSH.Rendering.session(80, 24)
      |> IO.iodata_to_binary()
      |> String.replace("\r\n", "\n")
      |> strip_ansi()

    assert rendered =~ "[compaction]"
    assert rendered =~ "Compacted from 1234 tokens (ctrl+o to expand)"
    refute rendered =~ "Summary"
  end

  test "ssh transport command parser handles session routing commands" do
    assert Tilde.Transport.SSH.Command.parse("/attach demo") == {:attach, "demo"}
    assert Tilde.Transport.SSH.Command.parse("/attach Demo Session!") == {:attach, "demo-session"}
    assert Tilde.Transport.SSH.Command.parse("/attach") == {:attach, "shared"}
    assert Tilde.Transport.SSH.Command.parse("/detach") == :detach
    assert Tilde.Transport.SSH.Command.parse("/session") == :session
    assert Tilde.Transport.SSH.Command.parse("hello") == :submit
    assert Tilde.Transport.SSH.Command.parse("/clear") == :submit
  end

  test "ssh delta classifier detects append-oriented tool updates" do
    started =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    streamed = Session.append_event(started, Tilde.tool_stream("tool_1", :stdout, "one\n"))
    streamed_more = Session.append_event(streamed, Tilde.tool_stream("tool_1", :stdout, "two\n"))

    done =
      Session.append_event(streamed_more, Tilde.tool_done("tool_1", :success, %{exit_code: 0}))

    assert {:new_blocks, [%Block{kind: :tool, id: "tool_1"}]} =
             Tilde.Transport.SSH.Delta.classify(Tilde.session(), started)

    assert {:tool_delta, %Block{id: "tool_1"}, :stdout, "one\n", true} =
             Tilde.Transport.SSH.Delta.classify(started, streamed)

    assert {:tool_delta, %Block{id: "tool_1"}, :stdout, "two\n", false} =
             Tilde.Transport.SSH.Delta.classify(streamed, streamed_more)

    assert {:tool_done, %Block{id: "tool_1", status: :success}} =
             Tilde.Transport.SSH.Delta.classify(streamed_more, done)
  end

  test "ssh delta classifier redraws non-append transcript changes" do
    collapsed =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    expanded = Session.toggle_tool_expansion(collapsed)

    assert Tilde.Transport.SSH.Delta.classify(collapsed, expanded) == :redraw
  end

  test "ssh shell applies tui keys to semantic session" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    assert {:cont, toggled} = Tilde.Transport.SSH.Shell.apply_key(session, :toggle_expand)
    assert [%Block{display: %{expanded?: true}}] = toggled.transcript.blocks
    assert {:halt, ^toggled} = Tilde.Transport.SSH.Shell.apply_key(toggled, :quit)
  end

  test "ssh channel submits exact slash command suggestions instead of accepting forever" do
    state = attached_ssh_state("ssh-exact-command")

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "/session\n"}},
               state
             )

    assert state.session.input.value == ""
  end

  test "ssh channel detach command returns to the index" do
    state = attached_ssh_state("ssh-detach-command")

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "/detach\n"}},
               state
             )

    assert state.session_server == nil
    assert state.session == nil
    assert state.session_id == nil
    refute state.attached?
    assert %Tilde.Core.Index{} = state.index
  end

  test "ssh channel opens palette and accepts focused workspace file" do
    state = attached_ssh_state("ssh-workspace-command")

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, <<16>>}},
               state
             )

    assert %Tilde.Core.Palette{open?: true, mode: :files} = state.palette

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "\n"}},
               state
             )

    assert state.workspace_mode == :file
    assert state.open_file.path != ""
    assert state.workspace.selected_path == state.open_file.path
  end

  test "ssh channel review shortcut opens the first review comment file from buffer scope" do
    state = attached_ssh_state("ssh-review-command")

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, <<16, ?\n>>}},
               state
             )

    assert state.workspace_mode == :file

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "r"}},
               state
             )

    assert state.workspace_mode == :file
    assert state.active_review_comment_id == "review-1"
    assert state.open_file.path != ""
  end

  defp attached_ssh_state(session_id) do
    {:ok, _pid} = Tilde.Session.Registry.ensure_started()
    server = Tilde.Session.Registry.via(session_id)

    assert {:ok, pid} =
             Tilde.Session.Server.ensure_started(server,
               session: Tilde.Demo.Live.demo_session(id: session_id)
             )

    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    session = Tilde.Session.Server.subscribe(server)
    workspace = Tilde.Runtime.WorkspaceFiles.workspace(session)

    %Tilde.Transport.SSH.Channel{
      session_server: server,
      session: session,
      session_id: session_id,
      attached?: true,
      workspace: workspace,
      review: Tilde.Demo.Live.demo_review(workspace),
      palette: Tilde.Core.Palette.new()
    }
  end

  test "tui key decoder maps terminal bytes to semantic actions" do
    assert Tilde.Core.Keys.decode(<<15>>) == :toggle_expand
    assert Tilde.Core.Keys.decode("q") == :quit
    assert Tilde.Core.Keys.decode("r") == :redraw
    assert Tilde.Core.Keys.decode("\t") == :tab
    assert Tilde.Core.Keys.decode("\e[Z") == :backtab
    assert Tilde.Core.Keys.decode("\r") == :enter
    assert Tilde.Core.Keys.decode(<<127>>) == :backspace
    assert Tilde.Core.Keys.decode(<<27>>) == :cancel
    assert Tilde.Core.Keys.decode(<<3>>) == :interrupt
    assert Tilde.Core.Keys.decode("a") == {:text, "a"}

    assert Tilde.Core.Keys.decode_many("q\r") == [:quit]
    assert Tilde.Core.Keys.decode_many("r\r") == [:redraw]

    assert Tilde.Core.Keys.decode_many("hello\r") == [
             {:text, "h"},
             {:text, "e"},
             {:text, "l"},
             {:text, "l"},
             {:text, "o"},
             :enter
           ]
  end
end
