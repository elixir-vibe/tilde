defmodule Tilde.Command.Builtin.Quit do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command.Builtin.Help

  def spec,
    do: Tilde.Command.Spec.new("/quit", "/quit", "Quit in SSH/TUI; not applicable on web")

  def run(_command, _session, _opts) do
    [Help.assistant("Use q or Ctrl+C to quit in SSH/TUI. Close the browser tab on web.")]
  end
end
