defmodule Tilde.Runtime.LLM do
  @moduledoc """
  Facade for model runtimes.

  The default implementation runs Jidoka turns with ReqLLM/OpenRouter and Jido
  action tools; callers depend only on this small boundary.
  """

  alias Tilde.Core.{AgentRuntime, Block, Session}
  alias Tilde.Session.Compaction

  @default_model "openrouter:~anthropic/claude-haiku-latest"
  @summary_errors [
    RuntimeError,
    ArgumentError,
    FunctionClauseError,
    MatchError,
    KeyError,
    Protocol.UndefinedError
  ]

  @doc "Returns the configured model id."
  @spec model() :: String.t()
  def model, do: Application.get_env(:tilde, :llm_model, @default_model)

  @doc "Returns true when automatic LLM responses should run."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:tilde, :llm_enabled, false)

  @doc "Streams assistant response events from the configured backend."
  @spec stream(Session.t(), keyword()) :: Enumerable.t(Jidoka.Event.t())
  def stream(%Session{} = session, opts \\ []) do
    Tilde.Runtime.LLM.Jidoka.stream(session, opts)
  end

  @doc "Resumes assistant response events from a checkpoint through the configured backend."
  @spec resume_checkpoint(Session.t(), AgentRuntime.t(), keyword()) ::
          Enumerable.t(Jidoka.Event.t())
  def resume_checkpoint(%Session{} = session, %AgentRuntime{} = runtime, opts \\ []) do
    Tilde.Runtime.LLM.Jidoka.resume_checkpoint(session, runtime, opts)
  end

  @doc "Builds the Jidoka failure event used when a runtime boundary fails before streaming."
  @spec failed_event(term(), keyword()) :: Jidoka.Event.t()
  def failed_event(reason, opts \\ []) do
    source = Keyword.get(opts, :source, "tilde-runtime")

    Jidoka.Event.build(:turn_failed, [],
      seq: Keyword.get(opts, :seq, 0),
      agent_id: source,
      request_id: source,
      loop_index: Keyword.get(opts, :iteration, 0),
      data: %{error: reason}
    )
  end

  @doc "Generates a semantic compaction summary through the configured backend."
  @spec summarize_compaction([Block.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def summarize_compaction(blocks, opts \\ []) when is_list(blocks) do
    Tilde.Runtime.LLM.Jidoka.summarize_compaction(blocks, opts)
  rescue
    exception in @summary_errors ->
      {:error, exception}
  end

  @doc "Cancels a checkpointed agent turn through the configured backend."
  @spec cancel_checkpoint(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def cancel_checkpoint(token, opts \\ []) when is_binary(token) do
    Tilde.Runtime.LLM.Jidoka.cancel_checkpoint(token, opts)
  end

  @doc "Returns the latest submitted user text, if present."
  @spec latest_user_text(Session.t()) :: String.t() | nil
  def latest_user_text(%Session{} = session) do
    session.transcript.blocks
    |> Enum.reverse()
    |> Enum.find_value(fn
      %Block{kind: :message, role: :user, source: text} when is_binary(text) -> text
      _block -> nil
    end)
  end

  @doc "Projects semantic message blocks to a compact text transcript."
  @spec prompt(Session.t()) :: String.t()
  def prompt(%Session{} = session) do
    history =
      session
      |> Compaction.model_context_blocks()
      |> Enum.filter(&message_block?/1)
      |> Enum.map_join("\n\n", fn %Block{role: role, source: source} ->
        "#{message_label(role)} #{String.trim(source)}"
      end)

    """
    Conversation so far:

    #{history}

    Reply to the latest user message. Keep the answer concise.
    """
  end

  defp message_block?(%Block{kind: :message, role: role, source: source})
       when role in [:user, :assistant, :system] and is_binary(source),
       do: true

  defp message_block?(_block), do: false

  defp message_label(:user), do: "User message:"
  defp message_label(:assistant), do: "Previous reply:"
  defp message_label(:system), do: "Compacted context:"
end
