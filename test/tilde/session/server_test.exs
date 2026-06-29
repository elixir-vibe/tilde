defmodule Tilde.Session.ServerTest do
  use TildeTest.Case

  alias Tilde.Core.AgentRuntime
  alias Tilde.Session.Server

  describe "commands" do
    test "command suggestions complete on tab and submit executable commands on enter" do
      assert %Tilde.Core.Suggest{title: "commands", items: items} =
               Tilde.Command.suggestions("/co")

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

      with_application_env(:llm_backend, TildeTest.LLMBackend, fn ->
        assert {:ok, command} = Tilde.Command.parse("/compact focus on decisions")
        compacted = Tilde.Command.apply_effects(session, Tilde.Command.run(command, session, []))

        assert length(compacted.events) == length(session.events) + 1

        assert %Tilde.Core.Event{type: :context_compacted, metadata: metadata} =
                 List.last(compacted.events)

        assert metadata.custom_instructions == "focus on decisions"
        assert metadata.first_kept_block_id
        assert List.last(compacted.transcript.blocks).role == :system
        assert List.last(compacted.transcript.blocks).source =~ "## Context Compaction"
      end)
    end

    test "compact command prefers configured LLM summary" do
      session = compactable_session()

      with_application_env(:llm_backend, TildeTest.CompactionSummaryLLMBackend, fn ->
        with_application_env(:compaction_summary_test_pid, self(), fn ->
          assert {:ok, command} = Tilde.Command.parse("/compact preserve blockers")

          compacted =
            Tilde.Command.apply_effects(session, Tilde.Command.run(command, session, []))

          assert_receive {:summarize_compaction, summarized_sources, opts}
          assert "one" in summarized_sources
          assert opts[:instructions] == "preserve blockers"

          assert List.last(compacted.transcript.blocks).source ==
                   "## Context Compaction\n\nLLM summary"
        end)
      end)
    end

    test "compact command falls back when configured LLM summary is blank" do
      session = compactable_session()

      with_application_env(:llm_backend, TildeTest.EmptyCompactionSummaryLLMBackend, fn ->
        assert {:ok, command} = Tilde.Command.parse("/compact")
        compacted = Tilde.Command.apply_effects(session, Tilde.Command.run(command, session, []))

        assert List.last(compacted.transcript.blocks).source =~
                 "Earlier conversation was compacted"

        assert List.last(compacted.transcript.blocks).source =~ "User: one"
      end)
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

      assert {:ok, pid} =
               Tilde.Session.Server.ensure_started(name, session: Tilde.session(id: id))

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
    end
  end

  describe "session lifecycle" do
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
  end

  describe "LLM runtime" do
    test "session server appends async assistant replies through Jidoka" do
      with_application_env(:llm_enabled, true, fn ->
        name = :"tilde_session_server_llm_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "llm_test"),
                   llm_opts: [llm: final_llm("echo: hello")]
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

    test "session server does not render max-iteration runtime fallback as assistant prose" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.MaxIterationsLLMBackend, fn ->
          name =
            :"tilde_session_server_terminal_result_test_#{System.unique_integer([:positive])}"

          assert {:ok, pid} =
                   Tilde.Session.Server.start_link(
                     name: name,
                     session: Tilde.session(id: "terminal_result")
                   )

          assert %Session{} = Tilde.Session.Server.subscribe(name)

          Tilde.Session.Server.append_event(name, Tilde.input_submitted("inspect"))

          session =
            wait_until_session(name, fn %Session{transcript: %{blocks: blocks}} ->
              Enum.any?(
                blocks,
                &match?(%Block{role: :assistant, source: "Let me inspect that:"}, &1)
              )
            end)

          assert [_, %Block{role: :assistant, source: source}] = session.transcript.blocks
          assert source == "Let me inspect that:"
          refute source =~ "Maximum iterations reached without a final answer."

          GenServer.stop(pid)
        end)
      end)
    end

    test "session server renders streamed LLM tool events as semantic tool blocks" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.ToolStreamingLLMBackend, fn ->
          name =
            :"tilde_session_server_llm_tool_stream_test_#{System.unique_integer([:positive])}"

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
        rate_limit = [
          scope: :"test_#{System.unique_integer([:positive])}",
          scale: :timer.minutes(1),
          limit: 0
        ]

        with_application_env(:llm_rate_limit, rate_limit, fn ->
          assert {:ok, _pid} = Tilde.Runtime.RateLimit.ensure_started()

          name =
            :"tilde_session_server_llm_rate_limit_test_#{System.unique_integer([:positive])}"

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

    test "session server projects Jidoka terminal metadata onto terminal assistant events" do
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

    test "session server projects Jidoka operation effects into tool transcript" do
      previous_key = System.get_env("OPENROUTER_API_KEY")
      System.put_env("OPENROUTER_API_KEY", "test-key")

      try do
        with_application_env(:llm_enabled, true, fn ->
          with_application_env(:llm_backend, TildeTest.JidokaToolLLMBackend, fn ->
            with_application_env(:jidoka_tool_llm_test_pid, self(), fn ->
              name =
                :"tilde_session_server_jidoka_tool_test_#{System.unique_integer([:positive])}"

              assert {:ok, pid} =
                       Tilde.Session.Server.start_link(
                         name: name,
                         session: Tilde.session(id: "jidoka_tool")
                       )

              assert %Session{} = Tilde.Session.Server.subscribe(name)
              Tilde.Session.Server.append_event(name, Tilde.input_submitted("what time is it?"))

              assert_receive :jidoka_tool_llm_operation_requested
              assert_receive :jidoka_tool_llm_final_requested

              session =
                wait_until_session(name, fn session ->
                  Enum.any?(session.transcript.blocks, &match?(%Block{kind: :tool}, &1)) and
                    Enum.any?(session.events, &(&1.type == :assistant_turn_finished))
                end)

              assert %Block{kind: :tool, name: "utc_now", args: %{}, status: :success} =
                       Enum.find(session.transcript.blocks, &match?(%Block{kind: :tool}, &1))

              assert Enum.any?(session.events, fn event ->
                       event.type == :assistant_done and event.text == "Tool finished."
                     end)

              finished = Enum.find(session.events, &(&1.type == :assistant_turn_finished))
              assert finished.metadata.jidoka.journal.operation_count == 1
              assert finished.metadata.jidoka.journal.operation_statuses == [:ok]
              assert [%{operation: "utc_now"}] = finished.metadata.jidoka.operations
              refute contains_process_identifier?(finished.metadata.jidoka)

              GenServer.stop(pid)
            end)
          end)
        end)
      after
        restore_system_env("OPENROUTER_API_KEY", previous_key)
      end
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
  end

  defp compactable_session do
    Tilde.session(id: "compactable")
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

  describe "dev snapshots" do
    test "dev snapshot includes resumable runtime for restored checkpoint metadata" do
      session =
        Tilde.session(id: "snapshot-resume")
        |> Session.put_agent_runtime(%AgentRuntime{
          active?: true,
          input_index: 4,
          block_id: "msg_assistant_4",
          queue_length: 0,
          run_id: "run-4",
          request_id: "request-4",
          checkpoint_token: "checkpoint-4",
          iteration: 3
        })

      {:ok, server} = Server.start_link(session: session)

      assert %{
               resume_runtime: %AgentRuntime{
                 input_index: 4,
                 block_id: "msg_assistant_4",
                 run_id: "run-4",
                 request_id: "request-4",
                 checkpoint_token: "checkpoint-4",
                 iteration: 3
               }
             } = Server.dev_snapshot(server)
    end

    test "dev snapshot suppresses resumable runtime while assistant is active" do
      session =
        Tilde.session(id: "snapshot-active")
        |> Session.append_event(Tilde.assistant_turn_started(block_id: "msg_assistant_2"))
        |> Session.put_agent_runtime(%AgentRuntime{
          active?: true,
          input_index: 2,
          block_id: "msg_assistant_2",
          queue_length: 0,
          run_id: "run-2",
          request_id: "request-2",
          checkpoint_token: "checkpoint-2",
          iteration: 1
        })

      {:ok, server} = Server.start_link(session: session)

      assert %{resume_runtime: nil} = Server.dev_snapshot(server)
    end
  end

  describe "event history" do
    test "session server keeps visible and raw history" do
      with_application_env(:llm_enabled, false, fn ->
        name = :"tilde_session_server_history_test_#{System.unique_integer([:positive])}"

        assert {:ok, pid} =
                 Tilde.Session.Server.start_link(
                   name: name,
                   session: Tilde.session(id: "history_test")
                 )

        Tilde.Session.Server.append_event(name, Tilde.input_submitted("one"))
        Tilde.Session.Server.append_event(name, Tilde.assistant_done("two"))
        updated = Tilde.Session.Server.append_event(name, Tilde.input_submitted("three"))

        assert Enum.map(updated.events, & &1.text) == ["one", "two", "three"]
        assert Enum.map(updated.transcript.blocks, & &1.source) == ["one", "two", "three"]

        GenServer.stop(pid)
      end)
    end
  end

  describe "storage" do
    test "persists newly appended events and draft state through configured storage" do
      with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
        with_application_env(:storage_test_pid, self(), fn ->
          {:ok, server} = Server.start_link(session: Tilde.session(id: "stored-session"))

          Server.append_event(server, Tilde.input_changed("draft"))
          Server.append_event(server, Tilde.input_submitted("hello"))

          assert_receive {:storage_save_state, "stored-session", "draft"}
          refute_receive {:storage_append_event, "stored-session", :input_changed, "draft"}
          assert_receive {:storage_append_event, "stored-session", :input_submitted, "hello"}
          assert_receive {:storage_save_state, "stored-session", ""}
        end)
      end)
    end

    test "persists command-generated events once" do
      with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
        with_application_env(:storage_test_pid, self(), fn ->
          {:ok, server} = Server.start_link(session: Tilde.session(id: "command-session"))

          Server.append_event(server, Tilde.input_submitted("/help"))

          assert_receive {:storage_append_event, "command-session", :input_submitted, "/help"}
          assert_receive {:storage_append_event, "command-session", :assistant_done, help_text}
          assert help_text =~ "/help"
          refute_receive {:storage_append_event, "command-session", :assistant_done, ^help_text}
        end)
      end)
    end

    test "persists boot-time checkpoint resume events and cleared metadata without historical duplicates" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.LLMBackend, fn ->
          with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
            with_application_env(:storage_test_pid, self(), fn ->
              session_id = "boot-resume-storage"
              {:ok, _server} = Server.start_link(session: resumable_session(session_id))

              types = collect_append_types(session_id, :assistant_turn_finished)

              assert :assistant_turn_started in types
              assert :assistant_done in types
              assert :assistant_turn_finished in types
              refute :input_submitted in types

              cleared =
                wait_for_agent_loop_metadata(session_id, fn metadata ->
                  match?(%{agent_loop: %{active?: false, checkpoint_token: nil}}, metadata)
                end)

              assert cleared.agent_loop.active? == false
            end)
          end)
        end)
      end)
    end

    test "persists boot-time checkpoint resume failure and cleared metadata" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.FailingLLMBackend, fn ->
          with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
            with_application_env(:storage_test_pid, self(), fn ->
              session_id = "boot-resume-failure-storage"
              {:ok, _server} = Server.start_link(session: resumable_session(session_id))

              types = collect_append_types(session_id, :assistant_turn_error)

              assert :assistant_turn_started in types
              assert :assistant_done in types
              assert :assistant_turn_error in types
              refute :input_submitted in types

              cleared =
                wait_for_agent_loop_metadata(session_id, fn metadata ->
                  match?(%{agent_loop: %{active?: false, checkpoint_token: nil}}, metadata)
                end)

              assert cleared.agent_loop.active? == false
            end)
          end)
        end)
      end)
    end

    test "persists boot-time checkpoint resume cancellation and cleared metadata" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.CancelledLLMBackend, fn ->
          with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
            with_application_env(:storage_test_pid, self(), fn ->
              session_id = "boot-resume-cancel-storage"
              {:ok, _server} = Server.start_link(session: resumable_session(session_id))

              types = collect_append_types(session_id, :assistant_turn_cancelled)

              assert :assistant_turn_started in types
              assert :assistant_turn_cancelled in types
              refute :input_submitted in types

              cleared =
                wait_for_agent_loop_metadata(session_id, fn metadata ->
                  match?(%{agent_loop: %{active?: false, checkpoint_token: nil}}, metadata)
                end)

              assert cleared.agent_loop.active? == false
            end)
          end)
        end)
      end)
    end

    test "persists sanitized agent loop checkpoint metadata and clears it after cancellation" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.CancellableLLMBackend, fn ->
          with_application_env(:cancellable_llm_test_pid, self(), fn ->
            with_application_env(:storage_adapter, TildeTest.StorageAdapter, fn ->
              with_application_env(:storage_test_pid, self(), fn ->
                {:ok, server} = Server.start_link(session: Tilde.session(id: "runtime-state"))

                Server.append_event(server, Tilde.input_submitted("checkpoint me"))

                assert_receive {:cancellable_llm_started, _task, _agent}

                checkpoint =
                  wait_for_agent_loop_metadata("runtime-state", fn metadata ->
                    get_in(metadata, [:agent_loop, :checkpoint_token]) == "checkpoint-123"
                  end)

                assert checkpoint.agent_loop.active? == true
                assert checkpoint.agent_loop.run_id == "test-run"
                assert checkpoint.agent_loop.request_id == "test-request"

                assert Tilde.Core.AgentRuntime.load(checkpoint.agent_loop).checkpoint_token ==
                         "checkpoint-123"

                refute contains_process_identifier?(checkpoint)

                Server.apply_interaction(server, %Tilde.Core.Interaction{type: :interrupt})

                cleared =
                  wait_for_agent_loop_metadata("runtime-state", fn metadata ->
                    match?(
                      %{agent_loop: %{active?: false, run_id: nil, checkpoint_token: nil}},
                      metadata
                    )
                  end)

                assert cleared.agent_loop.active? == false
                assert cleared.agent_loop.run_id == nil
                refute contains_process_identifier?(cleared)
              end)
            end)
          end)
        end)
      end)
    end

    defp resumable_session(session_id) do
      Tilde.session(id: session_id)
      |> Session.append_event(Tilde.input_submitted("historical prompt"))
      |> Session.put_agent_runtime(%Tilde.Core.AgentRuntime{
        active?: true,
        input_index: 1,
        block_id: "msg_assistant_2",
        queue_length: 0,
        run_id: "run",
        request_id: "request",
        checkpoint_token: "checkpoint-boot",
        iteration: 0
      })
    end

    defp collect_append_types(session_id, until_type, acc \\ []) do
      receive do
        {:storage_append_event, ^session_id, ^until_type, _text} ->
          Enum.reverse([until_type | acc])

        {:storage_append_event, ^session_id, type, _text} ->
          collect_append_types(session_id, until_type, [type | acc])

        _other ->
          collect_append_types(session_id, until_type, acc)
      after
        1_000 -> flunk("timed out waiting for #{inspect(until_type)} storage event")
      end
    end

    defp wait_for_agent_loop_metadata(session_id, predicate) do
      assert_receive {:storage_save_state_metadata, ^session_id, metadata}, 1_000

      if predicate.(metadata) do
        metadata
      else
        wait_for_agent_loop_metadata(session_id, predicate)
      end
    end

    defp contains_process_identifier?(pid) when is_pid(pid), do: true
    defp contains_process_identifier?(reference) when is_reference(reference), do: true

    defp contains_process_identifier?(map) when is_map(map) do
      Enum.any?(map, fn {key, value} ->
        contains_process_identifier?(key) or contains_process_identifier?(value)
      end)
    end

    defp contains_process_identifier?(list) when is_list(list) do
      Enum.any?(list, &contains_process_identifier?/1)
    end

    defp contains_process_identifier?(_value), do: false
  end

  describe "stream coalescing" do
    test "streams LLM deltas into one assistant block without exposing tiny intermediate chunks" do
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
                              blocks: [
                                %Block{role: :user},
                                %Block{role: :assistant, source: "hello"}
                              ]
                            }
                          } = streaming_session}

          assert_assistant_phase(streaming_session, :streaming)

          refute_receive {:tilde_session_updated, "llm_stream",
                          %Session{
                            transcript: %{
                              blocks: [
                                %Block{role: :user},
                                %Block{role: :assistant, source: "hel"}
                              ]
                            }
                          }}

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

    test "flushes buffered deltas even before completion" do
      with_application_env(:llm_enabled, true, fn ->
        with_application_env(:llm_backend, TildeTest.BufferedDeltaLLMBackend, fn ->
          with_application_env(:buffered_delta_llm_test_pid, self(), fn ->
            name =
              :"tilde_session_server_buffered_delta_test_#{System.unique_integer([:positive])}"

            assert {:ok, pid} =
                     Tilde.Session.Server.start_link(
                       name: name,
                       session: Tilde.session(id: "buffered_delta")
                     )

            assert %Session{} = Tilde.Session.Server.subscribe(name)
            Tilde.Session.Server.append_event(name, Tilde.input_submitted("hello"))
            assert_receive {:buffered_delta_llm_started, task}

            assert_receive_phase("buffered_delta", :waiting)

            assert_receive {:tilde_session_updated, "buffered_delta",
                            %Session{
                              transcript: %{
                                blocks: [
                                  %Block{role: :user},
                                  %Block{role: :assistant, source: "hello"}
                                ]
                              }
                            } = streaming_session}

            assert_assistant_phase(streaming_session, :streaming)

            refute_receive {:tilde_session_updated, "buffered_delta",
                            %Session{
                              transcript: %{
                                blocks: [
                                  %Block{role: :user},
                                  %Block{role: :assistant, source: "he"}
                                ]
                              }
                            }}

            send(task, :finish_buffered_delta_llm)

            assert_receive {:tilde_session_updated, "buffered_delta",
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
      end)
    end
  end

  defp final_llm(content) do
    fn _intent, _journal ->
      {:ok, Jidoka.Effect.LLMDecision.final(content)}
    end
  end
end
