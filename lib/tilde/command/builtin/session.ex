defmodule Tilde.Command.Builtin.Session do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command.Builtin.Help
  alias Tilde.Core.Session

  def spec,
    do: Tilde.Command.Spec.new("/session", "/session", "Show current session details")

  def run(_command, %Session{} = session, _opts) do
    text = """
    Session: #{session.id}
    Events: #{length(session.events)}
    Blocks: #{length(session.transcript.blocks)}
    """

    [Help.assistant(text)]
  end
end
