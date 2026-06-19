defmodule Tilde.Runtime.LLM.Provider do
  @moduledoc """
  Behaviour for model runtimes that stream assistant loop events from a Tilde session.
  """

  alias Tilde.Core.Session
  alias Tilde.Session.AgentLoop.ResumeCandidate

  @type stream_event :: Jido.AI.Runtime.Event.t()

  @callback stream(Session.t(), keyword()) :: Enumerable.t(stream_event())
  @callback resume_checkpoint(Session.t(), ResumeCandidate.t(), keyword()) ::
              Enumerable.t(stream_event())
  @callback cancel_checkpoint(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
