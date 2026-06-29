defmodule Tilde.Runtime.LLM.Provider.JidokaTest do
  use TildeTest.Case, async: false

  alias Tilde.Core.Session
  alias Tilde.Runtime.LLM.Provider.Jidoka, as: Provider

  test "hibernates a Jidoka turn with serialized snapshot and resumes it" do
    with_openrouter_key(fn ->
      session =
        Tilde.session(id: "jidoka-snapshot")
        |> Session.append_event(Tilde.input_submitted("latest question"))

      events =
        session
        |> Provider.stream(
          checkpoint: :before_each_effect,
          llm: __MODULE__.FinalLLM.llm("resumed answer")
        )
        |> Enum.to_list()

      assert %Jidoka.Event{event: :turn_hibernated, data: %{snapshot: snapshot}} =
               hibernated = List.last(events)

      assert String.starts_with?(snapshot, "jidoka:snapshot:v1:")
      refute_received :jidoka_final_llm_called

      candidate = %Tilde.Session.AgentLoop.ResumeCandidate{
        session_id: session.id,
        run_id: "tilde",
        request_id: hibernated.request_id,
        checkpoint_token: snapshot
      }

      assert [%Jidoka.Event{event: :turn_finished, data: %{result: "resumed answer"}}] =
               session
               |> Provider.resume_checkpoint(candidate,
                 llm: __MODULE__.FinalLLM.llm("resumed answer")
               )
               |> Enum.filter(&(&1.event == :turn_finished))
    end)
  end

  test "starts Jidoka turn with Tilde transcript as agent context" do
    with_openrouter_key(fn ->
      with_application_env(:jidoka_context_test_pid, self(), fn ->
        session =
          Tilde.session(id: "jidoka-context")
          |> Session.append_event(Tilde.input_submitted("earlier question"))
          |> Session.append_event(Tilde.assistant_done("earlier answer"))
          |> Session.append_event(Tilde.input_submitted("latest question"))

        _events =
          session
          |> Provider.stream(llm: __MODULE__.CaptureAndStop.llm())
          |> Enum.to_list()

        assert_receive {:jidoka_messages, messages}

        assert Enum.map(messages, & &1.role) == [:system, :user, :assistant, :user]

        assert Enum.map(messages, & &1.content) == [
                 system_prompt(messages),
                 "earlier question",
                 "earlier answer",
                 "latest question"
               ]
      end)
    end)
  end

  defp system_prompt([%{role: :system, content: prompt} | _]), do: prompt

  defp with_openrouter_key(fun) when is_function(fun, 0) do
    previous_key = System.get_env("OPENROUTER_API_KEY")
    System.put_env("OPENROUTER_API_KEY", "test-key")

    try do
      fun.()
    after
      restore_system_env("OPENROUTER_API_KEY", previous_key)
    end
  end

  defmodule FinalLLM do
    def llm(content) do
      caller = self()

      fn _intent, _journal ->
        send(caller, :jidoka_final_llm_called)
        {:ok, Jidoka.Effect.LLMDecision.final(content)}
      end
    end
  end

  defmodule CaptureAndStop do
    def llm do
      fn intent, _journal ->
        messages = get_in(intent.payload, [:prompt, :messages])

        send(
          Application.fetch_env!(:tilde, :jidoka_context_test_pid),
          {:jidoka_messages, messages}
        )

        {:ok, Jidoka.Effect.LLMDecision.final("captured")}
      end
    end
  end
end
