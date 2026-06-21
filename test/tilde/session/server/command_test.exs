defmodule Tilde.Session.Server.CommandTest do
  use TildeTest.Case

  test "command suggestions complete on tab and submit executable commands on enter" do
    assert %Tilde.Core.Suggest{title: "commands", items: items} = Tilde.Command.suggestions("/co")
    assert Enum.map(items, & &1.label) == ["/compact"]
    assert Tilde.Command.completion("/co") == "/compact"

    session = Session.append_event(Tilde.session(), Tilde.input_changed("/"))
    assert [suggest_widget] = Session.widgets(session, :above_input)
    assert %Tilde.Core.Suggest{selected_index: 0} = suggest_widget.content

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)
    assert html =~ "suggest"
    assert html =~ "/compact"
    assert html =~ "selected"
    assert html =~ "phx-click=\"tilde:complete_input\""

    assert {:cont, selected} = Tilde.Core.Controller.apply_key(session, :down)
    assert %Tilde.Core.Suggest{selected_index: 1} = Session.command_suggestions(selected)

    assert {:cont, completed} = Tilde.Core.Controller.apply_key(selected, :tab)

    assert completed.input.value ==
             Tilde.Command.completion(Session.command_suggestions(selected))

    assert {:cont, submitted} = Tilde.Core.Controller.apply_key(selected, :enter)

    assert submitted.input.value == ""
    assert [%Block{source: submitted_command}] = submitted.transcript.blocks
    assert submitted_command == Tilde.Command.completion(Session.command_suggestions(selected))
  end

  test "compact command appends visible summary without deleting raw history" do
    session =
      Tilde.session(id: "compact_command")
      |> Session.append_event(Tilde.input_submitted("one"))
      |> Session.append_event(Tilde.assistant_done("two"))
      |> Session.append_event(Tilde.input_submitted("three"))
      |> Session.append_event(Tilde.assistant_done("four"))
      |> Session.append_event(Tilde.input_submitted("five"))
      |> Session.append_event(Tilde.assistant_done("six"))
      |> Session.append_event(Tilde.input_submitted("seven"))
      |> Session.append_event(Tilde.assistant_done("eight"))
      |> Session.append_event(Tilde.input_submitted("nine"))
      |> Session.append_event(Tilde.assistant_done("ten"))

    assert {:ok, command} = Tilde.Command.parse("/compact focus on decisions")
    compacted = Tilde.Command.apply_effects(session, Tilde.Command.run(command, session, []))

    assert length(compacted.events) == length(session.events) + 1

    assert %Tilde.Core.Event{type: :context_compacted, metadata: metadata} =
             List.last(compacted.events)

    assert metadata.custom_instructions == "focus on decisions"
    assert metadata.first_kept_block_id
    assert List.last(compacted.transcript.blocks).role == :system
    assert List.last(compacted.transcript.blocks).source =~ "## Context Compaction"
  end

  test "command suggestions complete argument-taking commands instead of executing them" do
    session = Session.append_event(Tilde.session(), Tilde.input_changed("/"))

    assert {:cont, selected} = Tilde.Core.Controller.apply_key(session, :down)
    assert {:cont, selected} = Tilde.Core.Controller.apply_key(selected, :down)
    assert Tilde.Core.Suggest.selected(Session.command_suggestions(selected)).label == "/new"

    assert {:cont, completed} = Tilde.Core.Controller.apply_key(selected, :enter)

    assert completed.input.value == "/new "
    assert completed.transcript.blocks == []
    assert %Tilde.Core.Suggest{id: "new-session-hints"} = Session.command_suggestions(completed)

    assert {:cont, with_name} = Tilde.Core.Controller.apply_key(completed, {:text, "demo"})
    assert {:cont, submitted} = Tilde.Core.Controller.apply_key(with_name, :enter)

    assert submitted.input.value == ""
    assert [%Block{source: "/new demo"}] = submitted.transcript.blocks
  end

  test "attach command suggests sessions with bounded first and last message previews" do
    id = "preview-#{System.unique_integer([:positive])}"
    assert {:ok, _registry} = Tilde.Session.Registry.ensure_started()
    name = Tilde.Session.Registry.via(id)

    session =
      Tilde.session(id: id)
      |> Session.append_event(Tilde.input_submitted(String.duplicate("first message ", 8)))
      |> Session.append_event(Tilde.input_submitted(String.duplicate("last message ", 8)))

    assert {:ok, pid} = Tilde.Session.Server.ensure_started(name, session: session)

    assert %Tilde.Core.Suggest{title: "sessions  first → last", items: [item]} =
             Tilde.Command.suggestions("/attach #{id}")

    assert item.label == id
    assert item.insert == "/attach #{id}"
    assert item.description =~ "→"
    assert item.description =~ "…"
    assert item.detail =~ "First:"
    assert item.detail =~ "Last:"

    GenServer.stop(pid)
  end

  test "attach session suggestions submit selected session on enter" do
    id = "attach-#{System.unique_integer([:positive])}"
    assert {:ok, _registry} = Tilde.Session.Registry.ensure_started()
    name = Tilde.Session.Registry.via(id)
    assert {:ok, pid} = Tilde.Session.Server.ensure_started(name, session: Tilde.session(id: id))

    session = Session.append_event(Tilde.session(), Tilde.input_changed("/attach #{id}"))
    assert %Tilde.Core.Suggest{id: "session-suggestions"} = Session.command_suggestions(session)

    assert {:cont, submitted} = Tilde.Core.Controller.apply_key(session, :enter)

    assert submitted.input.value == ""

    assert [%Block{source: submitted_source}] = submitted.transcript.blocks
    assert submitted_source == "/attach #{id}"

    GenServer.stop(pid)
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
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "cmd_test")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("/help"))

        assert [%Block{role: :user, source: "/help"}, %Block{role: :assistant, source: source}] =
                 updated.transcript.blocks

        assert source =~ "/new [name]"

        refute_receive_phase("cmd_test", :waiting, 50)

        GenServer.stop(pid)
      end)
    end)
  end

  test "session registry names isolate session servers without dynamic atoms" do
    with_application_env(:llm_enabled, false, fn ->
      assert Tilde.Session.Registry.normalize_id("My Session!!") == "my-session"
      assert {:ok, _pid} = Tilde.Session.Registry.ensure_started()

      left = Tilde.Session.Registry.via("left-#{System.unique_integer([:positive])}")
      right = Tilde.Session.Registry.via("right-#{System.unique_integer([:positive])}")

      assert {:ok, left_pid} =
               Tilde.Session.Server.ensure_started(left, session: Tilde.session(id: "left"))

      assert {:ok, right_pid} =
               Tilde.Session.Server.ensure_started(right, session: Tilde.session(id: "right"))

      Tilde.Session.Server.append_event(left, Tilde.input_submitted("left only"))
      Tilde.Session.Server.append_event(right, Tilde.input_submitted("right only"))

      assert [%Block{source: "left only"}] =
               Tilde.Session.Server.get_session(left).transcript.blocks

      assert [%Block{source: "right only"}] =
               Tilde.Session.Server.get_session(right).transcript.blocks

      GenServer.stop(left_pid)
      GenServer.stop(right_pid)
    end)
  end

  test "session server mirrors one semantic session to subscribers" do
    name = :"tilde_session_server_test_#{System.unique_integer([:positive])}"
    session = Tilde.session(id: "mirror_test")

    assert {:ok, pid} = Tilde.Session.Server.start_link(name: name, session: session)
    assert %Session{id: "mirror_test"} = Tilde.Session.Server.subscribe(name)

    updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("from ssh"))

    assert [%Block{role: :user, source: "from ssh"}] = updated.transcript.blocks
    assert_receive {:tilde_session_updated, "mirror_test", ^updated}

    GenServer.stop(pid)
  end

  test "session server leaves submissions alone when LLM responses are disabled" do
    with_application_env(:llm_enabled, false, fn ->
      name = :"tilde_session_server_llm_disabled_test_#{System.unique_integer([:positive])}"

      assert {:ok, pid} =
               Tilde.Session.Server.start_link(
                 name: name,
                 session: Tilde.session(id: "llm_disabled")
               )

      assert %Session{} = Tilde.Session.Server.subscribe(name)

      updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

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
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_test")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

        assert_receive {:tilde_session_updated, "llm_test",
                        %Session{transcript: %{blocks: [_user]}}}

        assert_receive_phase("llm_test", :waiting)
        |> assert_assistant_waiting()

        assert_receive {:tilde_session_updated, "llm_test",
                        %Session{
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{role: :assistant, source: "echo: hello"}
                            ]
                          }
                        } = done_session}

        assert_assistant_phase(done_session, :done)

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server streams LLM deltas into one assistant block" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.StreamingLLMBackend, fn ->
        name = :"tilde_session_server_llm_stream_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_stream")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

        assert_receive_phase("llm_stream", :waiting)
        |> assert_assistant_waiting()

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{
                          transcript: %{
                            blocks: [%Block{role: :user}, %Block{role: :assistant, source: "hel"}]
                          }
                        } = streaming_session}

        assert_assistant_phase(streaming_session, :streaming)

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{role: :assistant, source: "hello"}
                            ]
                          }
                        } = streaming_session}

        assert_assistant_phase(streaming_session, :streaming)

        assert_receive {:tilde_session_updated, "llm_stream",
                        %Session{
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{role: :assistant, source: "hello"}
                            ]
                          }
                        } = done_session}

        assert_assistant_phase(done_session, :done)

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server keeps post-tool assistant text after tool without duplicating terminal result" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.PostToolTerminalLLMBackend, fn ->
        name =
          :"tilde_session_server_post_tool_terminal_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "post_tool_terminal")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("inspect"))

        session =
          wait_until_session(name, fn %Session{transcript: %{blocks: blocks}} ->
            Enum.map(blocks, & &1.kind) == [:message, :message, :tool, :message]
          end)

        assert [_, before_tool, tool, after_tool] = session.transcript.blocks
        assert %Block{role: :assistant, source: "Before."} = before_tool
        assert %Block{kind: :tool, name: "bash"} = tool
        assert %Block{role: :assistant, source: "After."} = after_tool

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server appends terminal runtime result when it differs from streamed text" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.MaxIterationsLLMBackend, fn ->
        name = :"tilde_session_server_terminal_result_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "terminal_result")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("inspect"))

        session =
          wait_until_session(name, fn %Session{transcript: %{blocks: blocks}} ->
            Enum.any?(blocks, fn
              %Block{role: :assistant, source: source} ->
                source =~ "Maximum iterations reached without a final answer."

              _block ->
                false
            end)
          end)

        assert [_, %Block{role: :assistant, source: source}] = session.transcript.blocks
        assert source =~ "Let me inspect that:"
        assert source =~ "Maximum iterations reached without a final answer."

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server renders streamed LLM tool events as semantic tool blocks" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.ToolStreamingLLMBackend, fn ->
        name = :"tilde_session_server_llm_tool_stream_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_tool_stream")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("what time is it?"))

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
          assert {:ok, _pid} = Tilde.Runtime.RateLimit.ensure_started()
          name = :"tilde_session_server_llm_rate_limit_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "llm_rate_limit")
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)

          Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

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

          refute_receive_phase("llm_rate_limit", :waiting, 50)

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
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_failure")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

        assert_receive {:tilde_session_updated, "llm_failure",
                        %Session{transcript: %{blocks: [_user]}}}

        assert_receive_phase("llm_failure", :waiting)

        assert_receive {:tilde_session_updated, "llm_failure",
                        %Session{
                          transcript: %{
                            blocks: [
                              %Block{role: :user},
                              %Block{
                                role: :assistant,
                                source: "The model is unavailable right now. Please try again."
                              }
                            ]
                          }
                        } = error_session}

        assert_assistant_phase(error_session, :error)

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server maps runtime cancellation events to cancelled assistant turns" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.CancelledLLMBackend, fn ->
        name =
          :"tilde_session_server_llm_runtime_cancel_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_runtime_cancel")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)
        Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

        assert_receive_phase("llm_runtime_cancel", :waiting)

        assert_receive_phase("llm_runtime_cancel", :cancelled)

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server recovers when LLM streams raise" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.CrashingLLMBackend, fn ->
        name = :"tilde_session_server_llm_crash_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_crash")
                 )

        assert %Session{} = Tilde.Session.Server.subscribe(name)
        Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))

        assert_receive_phase("llm_crash", :waiting)

        assert_receive {:tilde_session_updated, "llm_crash",
                        %Session{transcript: %{blocks: [_user, assistant]}} = error_session}

        assert_assistant_phase(error_session, :error)
        assert assistant.source == "The model is unavailable right now. Please try again."

        GenServer.stop(pid)
      end)
    end)
  end

  test "session server projects Jido terminal metadata onto terminal assistant events" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.BlockingMetadataLLMBackend, fn ->
        with_application_env(:metadata_llm_test_pid, self(), fn ->
          name = :"tilde_session_server_llm_metadata_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "llm_metadata")
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)
          Tilde.Session.Server.append_event(name, Tilde.input_submitted("semantic metadata"))
          assert_receive {:metadata_llm_started, task}

          assert %{agent_loop: %{active?: true, run_id: "test-run", request_id: "test-request"}} =
                   wait_until_session(name, fn session ->
                     match?(%{agent_loop: %{run_id: "test-run"}}, session.metadata)
                   end).metadata

          send(task, :release_metadata_llm)

          session =
            wait_until_session(name, fn session ->
              Enum.any?(session.events, &(&1.type == :assistant_turn_finished))
            end)

          finished = Enum.find(session.events, &(&1.type == :assistant_turn_finished))
          refute Map.has_key?(finished.metadata, :model)
          assert finished.metadata.usage == %{input_tokens: 21, output_tokens: 8}
          assert finished.metadata.termination_reason == :final_answer
          assert finished.metadata.thinking_content == "I should answer tersely."
          assert [%{summary: "reasoned"}] = finished.metadata.reasoning_details
          assert finished.metadata.checkpoint_token == "checkpoint-semantic"

          assert Session.agent_runtime(session).active? == false

          GenServer.stop(pid)
        end)
      end)
    end)
  end

  test "session server projects thinking deltas through existing assistant delta lifecycle" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.ThinkingLLMBackend, fn ->
        with_application_env(:thinking_llm_test_pid, self(), fn ->
          name = :"tilde_session_server_thinking_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "llm_thinking")
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)
          Tilde.Session.Server.append_event(name, Tilde.input_submitted("think"))
          assert_receive {:thinking_llm_started, task}

          thinking =
            wait_until_session(name, fn session ->
              Enum.any?(session.assistant.chunks, &(&1.type == :thinking))
            end)

          assert_assistant_phase(thinking, :thinking)

          assert [
                   %Block{role: :user},
                   %Block{role: :assistant, source: "", metadata: %{thinking: "thinking"}}
                 ] =
                   thinking.transcript.blocks

          send(task, :release_thinking_llm)

          streaming =
            wait_until_session(name, fn session ->
              Enum.any?(session.assistant.chunks, &(&1.type == :content))
            end)

          assert_assistant_phase(streaming, :streaming)

          assert [
                   %Block{role: :user},
                   %Block{role: :assistant, source: "answer", metadata: %{thinking: "thinking"}}
                 ] =
                   streaming.transcript.blocks

          send(task, :finish_thinking_llm)

          GenServer.stop(pid)
        end)
      end)
    end)
  end

  test "session server interrupt cancels checkpointed runtime and stream task" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.CancellableLLMBackend, fn ->
        with_application_env(:cancellable_llm_test_pid, self(), fn ->
          name = :"tilde_session_server_llm_cancel_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "llm_cancel")
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)
          Tilde.Session.Server.append_event(name, Tilde.input_submitted("stop me"))

          assert_receive {:cancellable_llm_started, task, agent}
          task_ref = Process.monitor(task)
          agent_ref = Process.monitor(agent)

          assert_receive {:tilde_session_updated, "llm_cancel",
                          %Session{transcript: %{blocks: [_, %Block{source: "working"}]}}}

          assert %{
                   agent_loop: %{
                     active?: true,
                     block_id: "msg_assistant_2",
                     queue_length: 0,
                     run_id: "test-run",
                     request_id: "test-request",
                     checkpoint_token: "checkpoint-123",
                     iteration: 0
                   }
                 } = Tilde.Session.Server.dev_snapshot(name)

          assert {:cont, %Session{} = cancelled, []} =
                   Tilde.Session.Server.apply_interaction(name, %Tilde.Core.Interaction{
                     type: :interrupt
                   })

          assert_assistant_phase(cancelled, :cancelled)

          assert %{agent_loop: %{active?: false, run_id: nil, checkpoint_token: nil}} =
                   Tilde.Session.Server.dev_snapshot(name)

          assert_receive {:cancellable_llm_cancelled, "checkpoint-123"}
          assert_receive {:DOWN, ^task_ref, :process, ^task, _reason}
          assert_receive {:DOWN, ^agent_ref, :process, ^agent, _reason}

          GenServer.stop(pid)
        end)
      end)
    end)
  end

  test "session server answers a queued submission after the active LLM response finishes" do
    with_application_env(:llm_enabled, true, fn ->
      with_application_env(:llm_backend, TildeTest.BlockingLLMBackend, fn ->
        with_application_env(:blocking_llm_test_pid, self(), fn ->
          name = :"tilde_session_server_llm_queue_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "llm_queue")
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)
          Tilde.Session.Server.append_event(name, Tilde.input_submitted("first"))
          assert_receive {:blocking_llm_started, first_task, "first"}

          Tilde.Session.Server.append_event(name, Tilde.input_submitted("second"))
          Tilde.Session.Server.append_event(name, Tilde.input_submitted("third"))
          send(first_task, :release_blocking_llm)

          assert_receive {:blocking_llm_started, second_task, "second"}, 1_000
          send(second_task, :release_blocking_llm)

          assert_receive {:blocking_llm_started, third_task, "third"}, 1_000
          send(third_task, :release_blocking_llm)

          sources = wait_for_sources("llm_queue", &("reply: first" in &1))
          assert "reply: first" in sources

          sources = wait_for_sources("llm_queue", &("reply: third" in &1))
          assert "first" in sources
          assert "second" in sources
          assert "third" in sources
          assert "reply: first" in sources
          assert "reply: second" in sources
          assert "reply: third" in sources

          GenServer.stop(pid)
        end)
      end)
    end)
  end

  defp wait_until_session(name, predicate, attempts \\ 20)

  defp wait_until_session(name, predicate, attempts) when attempts > 0 do
    session = Tilde.Session.Server.get_session(name)

    if predicate.(session) do
      session
    else
      Process.sleep(25)
      wait_until_session(name, predicate, attempts - 1)
    end
  end

  defp wait_until_session(name, _predicate, 0), do: Tilde.Session.Server.get_session(name)
end
