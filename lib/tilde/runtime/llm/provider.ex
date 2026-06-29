defmodule Tilde.Runtime.LLM.Provider do
  @moduledoc """
  Behaviour for model runtimes that stream assistant loop events from a Tilde session.
  """

  alias Tilde.Core.{AgentRuntime, Session}

  @type stream_event :: Jidoka.Event.t()

  @callback stream(Session.t(), keyword()) :: Enumerable.t(stream_event())
  @callback resume_checkpoint(Session.t(), AgentRuntime.t(), keyword()) ::
              Enumerable.t(stream_event())
  @callback cancel_checkpoint(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
