defmodule Tilde.Command.Builtin.Session do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Core.Session

  def spec,
    do: Tilde.Command.Spec.new("/session", "/session", "Show current session details")

  def run(_command, %Session{} = session, _opts) do
    text = """
    Session: #{session.id}
    Events: #{session.event_count}
    Blocks: #{length(session.transcript.blocks)}
    """

    [
      Tilde.Command.Effect.ShowSessionInfo.new(),
      Tilde.Command.Effect.AppendEvent.new(Tilde.assistant_done(text))
    ]
  end
end
