defmodule Tilde.Runtime.LLM do
  @moduledoc """
  Facade for model runtimes.

  The default implementation uses Jido.AI over ReqLLM/OpenRouter, and callers
  depend only on this small boundary.
  """

  alias Tilde.Core.{Block, Session}
  alias Tilde.Session.AgentLoop.ResumeCandidate
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

  @doc "Returns the configured LLM backend."
  @spec backend() :: module()
  def backend, do: Application.get_env(:tilde, :llm_backend, Tilde.Runtime.LLM.Provider.Jido)

  @doc "Returns the configured model id."
  @spec model() :: String.t()
  def model, do: Application.get_env(:tilde, :llm_model, @default_model)

  @doc "Returns true when automatic LLM responses should run."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:tilde, :llm_enabled, false)

  @doc "Streams assistant response events from the configured backend."
  @spec stream(Session.t(), keyword()) ::
          Enumerable.t(Tilde.Runtime.LLM.Provider.stream_event())
  def stream(%Session{} = session, opts \\ []) do
    backend = Keyword.get(opts, :backend, backend())
    backend.stream(session, opts)
  rescue
    exception in UndefinedFunctionError ->
      [Tilde.Runtime.LLM.Event.failed({:llm_backend_unavailable, exception.module})]
  end

  @doc "Resumes assistant response events from a checkpoint through the configured backend."
  @spec resume_checkpoint(Session.t(), ResumeCandidate.t(), keyword()) ::
          Enumerable.t(Tilde.Runtime.LLM.Provider.stream_event())
  def resume_checkpoint(%Session{} = session, %ResumeCandidate{} = candidate, opts \\ []) do
    backend = Keyword.get(opts, :backend, backend())
    backend.resume_checkpoint(session, candidate, opts)
  rescue
    exception in UndefinedFunctionError ->
      [Tilde.Runtime.LLM.Event.failed({:llm_backend_unavailable, exception.module})]
  end

  @doc "Generates a semantic compaction summary through the configured backend."
  @spec summarize_compaction([Block.t()], keyword()) :: {:ok, String.t()} | {:error, term()}
  def summarize_compaction(blocks, opts \\ []) when is_list(blocks) do
    backend = Keyword.get(opts, :backend, backend())

    if function_exported?(backend, :summarize_compaction, 2) do
      backend.summarize_compaction(blocks, opts)
    else
      {:error, :unsupported_compaction_summary}
    end
  rescue
    exception in UndefinedFunctionError ->
      {:error, {:llm_backend_unavailable, exception.module}}

    exception in @summary_errors ->
      {:error, exception}
  end

  @doc "Cancels a checkpointed ReAct run through the configured backend."
  @spec cancel_checkpoint(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def cancel_checkpoint(token, opts \\ []) when is_binary(token) do
    backend = Keyword.get(opts, :backend, backend())
    backend.cancel_checkpoint(token, opts)
  rescue
    exception in UndefinedFunctionError ->
      {:error, {:llm_backend_unavailable, exception.module}}
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
