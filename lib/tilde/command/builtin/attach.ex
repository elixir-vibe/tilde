defmodule Tilde.Command.Builtin.Attach do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command
  alias Tilde.Command.Builtin.Help
  alias Tilde.Session.Registry

  def spec,
    do: Tilde.Command.Spec.new("/attach", "/attach ", "Attach SSH/TUI to a named session")

  def run(%Command{args: ""}, _session, _opts),
    do: [Tilde.Command.Effect.AttachSession.new("shared")]

  def run(%Command{args: args}, _session, _opts) do
    id = Registry.normalize_id(args)
    [Tilde.Command.Effect.AttachSession.new(id), Help.assistant("Attached to session: #{id}")]
  end
end
