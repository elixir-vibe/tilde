defmodule Tilde.Command.Builtin.Detach do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command.Builtin.Help

  def spec,
    do: Tilde.Command.Spec.new("/detach", "/detach", "Detach SSH/TUI to a new private session")

  def run(_command, _session, _opts) do
    [
      Help.assistant(
        "SSH/TUI detaches with `/detach`; web sessions can navigate to another `/tilde/:id`."
      )
    ]
  end
end
