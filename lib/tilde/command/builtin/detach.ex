defmodule Tilde.Command.Builtin.Detach do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  def spec,
    do: Tilde.Command.Spec.new("/detach", "/detach", "Detach SSH/TUI to a new private session")

  def run(_command, _session, _opts), do: [Tilde.Command.Effect.DetachSession.new()]
end
