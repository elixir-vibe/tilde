defmodule Tilde.Command.Builtin.Showcase do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Core.Session

  def spec,
    do: Tilde.Command.Spec.new("/showcase", "/showcase", "Append the demo showcase")

  def run(_command, %Session{} = session, _opts) do
    [Tilde.Command.Effect.ReplaceSession.new(Tilde.Demo.Showcase.append(session))]
  end
end
