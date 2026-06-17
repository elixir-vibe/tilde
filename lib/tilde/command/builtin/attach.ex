defmodule Tilde.Command.Builtin.Attach do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command
  alias Tilde.Command.Builtin.Help
  alias Tilde.Core.Suggest
  alias Tilde.Session.{Registry, Summary}

  def spec,
    do: Tilde.Command.Spec.new("/attach", "/attach ", "Attach SSH/TUI to a named session")

  def run(%Command{args: ""}, _session, _opts),
    do: [Tilde.Command.Effect.AttachSession.new("shared")]

  def run(%Command{args: args}, _session, _opts) do
    id = Registry.normalize_id(args)
    [Tilde.Command.Effect.AttachSession.new(id), Help.assistant("Attached to session: #{id}")]
  end

  def suggest_args(%Command{args: query}, _opts) do
    query = query |> String.downcase() |> String.trim_leading()

    items =
      Summary.list()
      |> Enum.filter(fn summary -> String.starts_with?(summary.id, query) end)
      |> Enum.map(&Summary.to_suggest_item(&1, insert: "/attach #{&1.id}"))

    if items == [] do
      nil
    else
      Suggest.new(
        id: "session-suggestions",
        title: "sessions  first → last",
        trigger: "/attach ",
        query: query,
        items: items
      )
    end
  end
end
