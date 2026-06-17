defmodule Tilde.Runtime.LLM.Provider do
  @moduledoc """
  Behaviour for model runtimes that can answer from a Tilde session.
  """

  alias Tilde.Core.Session

  @type stream_event ::
          {:delta, String.t()}
          | {:done, String.t()}
          | {:error, term()}
          | {:tool_preparing, String.t(), String.t(), map()}
          | {:tool_started, String.t(), String.t(), map()}
          | {:tool_done, String.t(), atom(), term()}

  @callback respond(Session.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback stream(Session.t(), keyword()) :: Enumerable.t(stream_event())

  @optional_callbacks stream: 2
end
