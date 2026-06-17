defmodule Tilde.Command.Builtin.New do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command
  alias Tilde.Command.Builtin.Help

  def spec, do: Tilde.Command.Spec.new("/new", "/new ", "Start an isolated web session")

  def run(%Command{args: args}, _session, _opts) do
    id = Command.new_session_id(args)
    [{:new_session, id}, Help.assistant("New isolated session: /tilde/#{id}")]
  end
end
