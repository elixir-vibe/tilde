defmodule Tilde.Command.Builtin.Help do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  @help """
  Available commands:

  - `/help` — Show this help
  - `/showcase` — Append the semantic console showcase
  - `/new [name]` — Start an isolated web session
  - `/attach <name>` — Attach SSH/TUI to a named session
  - `/detach` — Detach SSH/TUI to a new private session
  - `/session` — Show current session details
  - `/clear` — Clear this session
  - `/quit` — Quit in SSH/TUI; not applicable on web
  """

  def spec, do: Tilde.Command.Spec.new("/help", "/help", "Show this help")
  def run(_command, _session, _opts), do: [assistant(@help)]

  def assistant(text), do: Tilde.Command.Effect.AppendEvent.new(Tilde.assistant_done(text))
end
