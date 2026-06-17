defmodule Tilde.Command.Builtin.Clear do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Core.Session

  def spec, do: Tilde.Command.Spec.new("/clear", "/clear", "Clear this session")

  def run(_command, %Session{} = session, opts) do
    seed = Keyword.get(opts, :seed)
    cleared = if is_function(seed, 1), do: seed.(session.id), else: Tilde.session(id: session.id)
    [{:replace_session, cleared}]
  end
end
