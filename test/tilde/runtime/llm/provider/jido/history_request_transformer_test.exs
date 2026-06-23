defmodule Tilde.Runtime.LLM.Provider.Jido.HistoryRequestTransformerTest do
  use TildeTest.Case, async: true

  alias Tilde.Runtime.LLM.Provider.Jido.HistoryRequestTransformer

  test "injects transcript history between system prompt and current query" do
    request = %{
      messages: [
        %{role: :system, content: "system"},
        %{role: :user, content: "latest question"}
      ],
      tools: %{},
      llm_opts: [],
      model: :test
    }

    runtime_context = %{
      messages: [
        %{role: :user, content: "earlier question"},
        %{role: :assistant, content: "earlier answer"}
      ]
    }

    assert {:ok, %{messages: messages}} =
             HistoryRequestTransformer.transform_request(request, nil, nil, runtime_context)

    assert messages == [
             %{role: :system, content: "system"},
             %{role: :user, content: "earlier question"},
             %{role: :assistant, content: "earlier answer"},
             %{role: :user, content: "latest question"}
           ]
  end

  test "ignores malformed history entries" do
    request = %{messages: [%{role: :user, content: "latest"}]}

    runtime_context = %{
      messages: [
        %{"role" => "user", "content" => "kept"},
        %{"role" => "unknown", "content" => "dropped"},
        %{role: :assistant, content: 123}
      ]
    }

    assert {:ok, %{messages: messages}} =
             HistoryRequestTransformer.transform_request(request, nil, nil, runtime_context)

    assert messages == [
             %{role: :user, content: "kept"},
             %{role: :user, content: "latest"}
           ]
  end

  test "leaves requests unchanged when no history exists" do
    request = %{messages: [%{role: :user, content: "latest"}]}

    assert {:ok, ^request} = HistoryRequestTransformer.transform_request(request, nil, nil, %{})
  end
end
