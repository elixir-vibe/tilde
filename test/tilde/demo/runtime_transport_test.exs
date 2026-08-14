defmodule Tilde.DemoRuntimeTransportTest do
  use TildeTest.Case

  alias Tilde.Index
  alias Tilde.Session.Controller

  test "Jidoka runtime reports a missing OpenRouter key before calling the runtime" do
    previous = System.get_env("OPENROUTER_API_KEY")
    System.delete_env("OPENROUTER_API_KEY")

    assert [
             %Jidoka.Event{
               event: :turn_failed,
               data: %{error: :missing_openrouter_api_key}
             }
           ] =
             Enum.to_list(Tilde.Runtime.LLM.Jidoka.stream(Tilde.session()))

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
    assert {:cont, session} = Controller.apply_key(Tilde.session(), {:text, "h"})
    assert {:cont, session} = Controller.apply_key(session, {:text, "i"})
    assert session.input.value == "hi"

    assert {:cont, session} = Controller.apply_key(session, :backspace)
    assert session.input.value == "h"

    assert {:cont, session} = Controller.apply_key(session, {:text, "!"})
    assert {:cont, submitted} = Controller.apply_key(session, :enter)

    assert submitted.input.value == ""
    assert [%Block{role: :user, source: "h!"}] = submitted.transcript.blocks
  end

  test "tui controller applies keys to semantic session" do
    session =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    assert {:cont, toggled} = Controller.apply_key(session, :toggle_expand)
    assert [%Block{display: %{expanded?: true}}] = toggled.transcript.blocks
    assert {:halt, ^toggled} = Controller.apply_key(toggled, :quit)
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

  test "ssh delta classifier detects append-oriented tool updates" do
    started =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )

    streamed = Session.append_event(started, Tilde.tool_stream("tool_1", :stdout, "one\n"))
    streamed_more = Session.append_event(streamed, Tilde.tool_stream("tool_1", :stdout, "two\n"))

    streamed_stderr =
      Session.append_event(streamed_more, Tilde.tool_stream("tool_1", :stderr, "warn\n"))

    done =
      Session.append_event(streamed_stderr, Tilde.tool_done("tool_1", :success, %{exit_code: 0}))

    assert {:new_blocks, [%Block{kind: :tool, id: "tool_1"}]} =
             Tilde.Transport.SSH.Delta.classify(Tilde.session(), started)

    assert {:tool_delta, %Block{id: "tool_1"}, :stdout, "one\n", true} =
             Tilde.Transport.SSH.Delta.classify(started, streamed)

    assert {:tool_delta, %Block{id: "tool_1"}, :stdout, "two\n", false} =
             Tilde.Transport.SSH.Delta.classify(streamed, streamed_more)

    assert {:tool_delta, %Block{id: "tool_1"}, :stderr, "warn\n", true} =
             Tilde.Transport.SSH.Delta.classify(streamed_more, streamed_stderr)

    assert {:tool_done, %Block{id: "tool_1", status: :success}} =
             Tilde.Transport.SSH.Delta.classify(streamed_stderr, done)
  end

  test "ssh delta classifier redraws non-append stream changes" do
    old =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )
      |> Session.append_event(Tilde.tool_stream("tool_1", :stdout, "one\n"))

    replacement =
      Tilde.session()
      |> Session.append_event(
        Tilde.tool_started("bash", %{command: "mix test"}, tool_call_id: "tool_1")
      )
      |> Session.append_event(Tilde.tool_stream("tool_1", :stdout, "different\n"))

    assert Tilde.Transport.SSH.Delta.classify(old, replacement) == :redraw
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
    assert %Index{} = state.index
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

    assert {:ok, state} = open_first_ssh_file(state)

    assert state.workspace_mode == :file

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "r"}},
               state
             )

    assert state.workspace_mode == :file
    assert state.active_review_comment_id == first_review_comment_id(state)
    assert state.open_file.path != ""
  end

  test "ssh channel navigates next and previous review comments from buffer scope" do
    state = attached_ssh_state("ssh-review-navigation-command")

    assert {:ok, state} = open_first_ssh_file(state)

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "r"}},
               state
             )

    [first_id, second_id | _rest] = review_comment_ids(state)
    assert state.active_review_comment_id == first_id

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "n"}},
               state
             )

    assert state.active_review_comment_id == second_id
    assert state.open_file.path == Tilde.Core.Review.find_comment(state.review, second_id).path

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "p"}},
               state
             )

    assert state.active_review_comment_id == first_id
  end

  test "ssh channel toggles the active review comment resolved and open" do
    state = attached_ssh_state("ssh-review-toggle-command")

    assert {:ok, state} = open_first_ssh_file(state)

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "r"}},
               state
             )

    comment_id = first_review_comment_id(state)

    assert %{status: :open} = Tilde.Core.Review.find_comment(state.review, comment_id)

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "x"}},
               state
             )

    assert state.active_review_comment_id == comment_id
    assert %{status: :resolved} = Tilde.Core.Review.find_comment(state.review, comment_id)

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "x"}},
               state
             )

    assert %{status: :open} = Tilde.Core.Review.find_comment(state.review, comment_id)
  end

  test "ssh channel scrolls the open file with page keys" do
    state = attached_ssh_state("ssh-file-scroll-command")

    assert {:ok, state} = open_first_ssh_file(%{state | height: 20})
    assert state.file_scroll_line == 1

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "\e[6~"}},
               state
             )

    assert state.file_scroll_line > 1
    scrolled_line = state.file_scroll_line

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "\e[5~"}},
               state
             )

    assert state.file_scroll_line < scrolled_line
    assert state.workspace_mode == :file
  end

  test "ssh buffer shortcuts are not blocked by hidden chat draft text" do
    state = attached_ssh_state("ssh-review-hidden-draft-command")

    assert {:ok, state} = open_first_ssh_file(state)

    state = %{state | session: Session.append_event(state.session, Tilde.input_changed("draft"))}

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "r"}},
               state
             )

    comment_id = first_review_comment_id(state)

    assert {:ok, state} =
             Tilde.Transport.SSH.Channel.handle_ssh_msg(
               {:ssh_cm, nil, {:data, nil, 0, "x"}},
               state
             )

    assert state.active_review_comment_id == comment_id
    assert %{status: :resolved} = Tilde.Core.Review.find_comment(state.review, comment_id)
  end

  defp open_first_ssh_file(state) do
    Tilde.Transport.SSH.Channel.handle_ssh_msg(
      {:ssh_cm, nil, {:data, nil, 0, <<16, ?\n>>}},
      state
    )
  end

  defp attached_ssh_state(session_id) do
    {:ok, _pid} = Tilde.Session.Registry.ensure_started()
    server = Tilde.Session.Registry.via(session_id)

    session =
      Tilde.Demo.Live.demo_session(id: session_id)
      |> Session.append_event(
        Tilde.tool_started("edit", %{path: "lib/tilde/core/review.ex"}, tool_call_id: "edit-1")
      )
      |> Session.append_event(
        Tilde.tool_started("edit", %{path: "lib/tilde/demo/live.ex"}, tool_call_id: "edit-2")
      )

    assert {:ok, pid} =
             Tilde.Session.Server.ensure_started(server,
               session: session
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
      review: Tilde.Runtime.WorkspaceReview.review(workspace, session),
      palette: Tilde.Core.Palette.new()
    }
  end

  defp first_review_comment_id(state) do
    state
    |> review_comment_ids()
    |> List.first()
  end

  defp review_comment_ids(state) do
    state.review
    |> Tilde.Core.Review.comments()
    |> Enum.map(& &1.id)
  end

  test "tui key decoder maps terminal bytes to semantic actions" do
    assert Tilde.Core.Keys.decode(<<15>>) == :toggle_expand
    assert Tilde.Core.Keys.decode("q") == :quit
    assert Tilde.Core.Keys.decode("r") == :redraw
    assert Tilde.Core.Keys.decode("\t") == :tab
    assert Tilde.Core.Keys.decode("\e[Z") == :backtab
    assert Tilde.Core.Keys.decode("\e[5~") == :page_up
    assert Tilde.Core.Keys.decode("\e[6~") == :page_down
    assert Tilde.Core.Keys.decode("\r") == :enter
    assert Tilde.Core.Keys.decode(<<127>>) == :backspace
    assert Tilde.Core.Keys.decode(<<27>>) == :cancel
    assert Tilde.Core.Keys.decode(<<3>>) == :interrupt
    assert Tilde.Core.Keys.decode("a") == {:text, "a"}

    assert Tilde.Core.Keys.decode_many("q\r") == [:quit]
    assert Tilde.Core.Keys.decode_many("r\r") == [:redraw]
    assert Tilde.Core.Keys.decode_many("\e[5~\e[6~") == [:page_up, :page_down]

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
