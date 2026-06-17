defmodule Tilde.Session.PromptRunner do
  @moduledoc "Task-based safe runner for streaming prompt backends."

  alias Tilde.Core.Session
  alias Tilde.Runtime.LLM

  @type stream_fun :: (Session.t() -> Enumerable.t(Tilde.Runtime.LLM.Provider.stream_event()))

  @spec start(Session.t(), pid(), reference(), keyword()) :: {:ok, pid()}
  def start(%Session{} = session, parent, ref, opts \\ []) when is_pid(parent) do
    stream_fun = Keyword.get(opts, :stream_fun, &LLM.stream/1)

    Task.start(fn -> stream_to_parent(stream_fun, session, parent, ref) end)
  end

  @spec cancel(pid() | nil) :: :ok
  def cancel(nil), do: :ok

  def cancel(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Process.exit(pid, :kill)
    :ok
  end

  defp stream_to_parent(stream_fun, %Session{} = session, parent, ref) do
    stream_fun.(session)
    |> Enum.each(&send(parent, {:tilde_prompt_stream, ref, &1}))
  rescue
    exception in [
      RuntimeError,
      ArgumentError,
      ArithmeticError,
      MatchError,
      FunctionClauseError,
      CaseClauseError,
      CondClauseError,
      WithClauseError,
      KeyError,
      BadMapError,
      Protocol.UndefinedError,
      UndefinedFunctionError
    ] ->
      send(parent, {:tilde_prompt_stream, ref, {:error, {:exception, :error, exception}}})
  catch
    kind, reason ->
      send(parent, {:tilde_prompt_stream, ref, {:error, {:exception, kind, reason}}})
  end
end
