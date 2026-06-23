defmodule Tilde.Runtime.LLM.Provider.JidoContextTest do
  use TildeTest.Case, async: false

  alias Tilde.Core.Session
  alias Tilde.Runtime.LLM.Provider.Jido

  test "starts standalone ReAct with Tilde transcript as Jido context" do
    previous_key = System.get_env("OPENROUTER_API_KEY")
    System.put_env("OPENROUTER_API_KEY", "test-key")

    try do
      with_application_env(:jido_context_test_pid, self(), fn ->
        session =
          Tilde.session(id: "jido-context")
          |> Session.append_event(Tilde.input_submitted("earlier question"))
          |> Session.append_event(Tilde.assistant_done("earlier answer"))
          |> Session.append_event(Tilde.input_submitted("latest question"))

        _events =
          session
          |> Jido.stream(request_transformer: __MODULE__.CaptureAndStop)
          |> Enum.to_list()

        assert_receive {:jido_messages, messages}

        assert Enum.map(messages, & &1.role) == [:system, :user, :assistant, :user]

        assert Enum.map(messages, & &1.content) == [
                 system_prompt(messages),
                 "earlier question",
                 "earlier answer",
                 "latest question"
               ]
      end)
    after
      restore_system_env("OPENROUTER_API_KEY", previous_key)
    end
  end

  defp system_prompt([%{role: :system, content: prompt} | _]), do: prompt

  defmodule CaptureAndStop do
    def transform_request(%{messages: messages}, _state, _config, _runtime_context) do
      send(Application.fetch_env!(:tilde, :jido_context_test_pid), {:jido_messages, messages})
      {:error, :captured}
    end
  end
end
