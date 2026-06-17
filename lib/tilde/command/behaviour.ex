defmodule Tilde.Command.Behaviour do
  @moduledoc """
  Behaviour for semantic slash commands.
  """

  alias Tilde.Command
  alias Tilde.Command.Effect
  alias Tilde.Core.Session

  @callback spec() :: Tilde.Command.Spec.t()
  @callback run(Command.t(), Session.t(), keyword()) :: [Effect.t()]
  @callback suggest_args(Command.t(), keyword()) :: Tilde.Core.Suggest.t() | nil

  @optional_callbacks suggest_args: 2
end
