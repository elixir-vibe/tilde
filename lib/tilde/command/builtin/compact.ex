defmodule Tilde.Command.Builtin.Compact do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Core.Session

  def spec,
    do: Tilde.Command.Spec.new("/compact", "/compact", "Trim older session history")

  def run(_command, %Session{} = session, opts) do
    limit =
      Keyword.get(opts, :limit, Application.get_env(:tilde, :command_compact_event_limit, 40))

    compacted =
      session
      |> Session.trim_events(limit)
      |> Session.append_event(
        Tilde.assistant_done("Compacted session history to the latest #{limit} events.")
      )

    [Tilde.Command.Effect.ReplaceSession.new(compacted)]
  end
end
