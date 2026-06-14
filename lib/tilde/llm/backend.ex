defmodule Tilde.LLM.Backend do
  @moduledoc """
  Behaviour for model runtimes that can answer from a Tilde session.
  """

  alias Tilde.Session

  @type stream_event :: {:delta, String.t()} | {:done, String.t()} | {:error, term()}

  @callback respond(Session.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback stream(Session.t(), keyword()) :: Enumerable.t(stream_event())

  @optional_callbacks stream: 2
end
