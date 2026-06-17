defmodule Tilde.Command.Behaviour do
  @moduledoc """
  Behaviour for semantic slash commands.
  """

  alias Tilde.Command
  alias Tilde.Command.Effect
  alias Tilde.Core.Session

  @callback spec() :: Tilde.Command.Spec.t()
  @callback run(Command.t(), Session.t(), keyword()) :: [Effect.t()]
end
