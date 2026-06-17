defmodule Tilde.Command.Builtin.New do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command
  alias Tilde.Command.Builtin.Help
  alias Tilde.Core.Suggest
  alias Tilde.Core.Suggest.Item

  def spec, do: Tilde.Command.Spec.new("/new", "/new ", "Start an isolated web session")

  def suggest_args(%Command{args: query}, _opts) do
    query = String.trim_leading(query)

    Suggest.new(
      id: "new-session-hints",
      title: "session name",
      trigger: "/new ",
      query: query,
      items: [
        Item.new(
          id: "session-name",
          label: "name",
          insert: "/new #{query}",
          description: "letters, numbers, dash, underscore",
          detail: "Type a session name. Other characters are normalized to dashes."
        )
      ]
    )
  end

  def run(%Command{args: args}, _session, _opts) do
    id = Command.new_session_id(args)

    [
      Tilde.Command.Effect.NewSession.new(id),
      Help.assistant("New isolated session: /tilde/#{id}")
    ]
  end
end
