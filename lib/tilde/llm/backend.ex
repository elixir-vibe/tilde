defmodule Tilde.LLM.Backend do
  @moduledoc """
  Behaviour for model runtimes that can answer from a Tilde session.
  """

  alias Tilde.Session

  @callback respond(Session.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
end
