defmodule Tilde.Session.Server.StorageTest do
  use TildeTest.Case, async: false

  alias Tilde.Session.Server

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
