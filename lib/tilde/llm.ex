defmodule Tilde.LLM do
  @moduledoc """
  Facade for optional model runtimes.

  The default implementation uses Jido.AI over ReqLLM/OpenRouter, but callers
  depend only on this small boundary.
  """

  alias Tilde.{Block, Session}

  @default_model "openrouter:~anthropic/claude-haiku-latest"

  @doc "Returns the configured LLM backend."
  @spec backend() :: module()
  def backend, do: Application.get_env(:tilde, :llm_backend, Tilde.LLM.Jido)

  @doc "Returns the configured model id."
  @spec model() :: String.t()
  def model, do: Application.get_env(:tilde, :llm_model, @default_model)

  @doc "Returns true when automatic LLM responses should run."
  @spec enabled?() :: boolean()
  def enabled?, do: Application.get_env(:tilde, :llm_enabled, false)

  @doc "Generates an assistant response from the session via the configured backend."
  @spec respond(Session.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def respond(%Session{} = session, opts \\ []) do
    backend = Keyword.get(opts, :backend, backend())

    if backend_function?(backend, :respond) do
      backend.respond(session, opts)
    else
      {:error, {:llm_backend_unavailable, backend}}
    end
  end

  @doc "Streams assistant response events from the configured backend."
  @spec stream(Session.t(), keyword()) :: Enumerable.t(Tilde.LLM.Backend.stream_event())
  def stream(%Session{} = session, opts \\ []) do
    backend = Keyword.get(opts, :backend, backend())

    cond do
      backend_function?(backend, :stream) ->
        backend.stream(session, opts)

      backend_function?(backend, :respond) ->
        Stream.map([respond(session, opts)], fn
          {:ok, text} -> {:done, text}
          {:error, reason} -> {:error, reason}
        end)

      true ->
        [{:error, {:llm_backend_unavailable, backend}}]
    end
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
      session.transcript.blocks
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
       when role in [:user, :assistant] and is_binary(source),
       do: true

  defp message_block?(_block), do: false

  defp backend_function?(backend, name) do
    Code.ensure_loaded?(backend) and function_exported?(backend, name, 2)
  end

  defp message_label(:user), do: "User message:"
  defp message_label(:assistant), do: "Previous reply:"
end
