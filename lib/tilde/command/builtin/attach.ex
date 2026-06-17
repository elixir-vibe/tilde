defmodule Tilde.Command.Builtin.Attach do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command
  alias Tilde.Command.Builtin.Attach.Preview
  alias Tilde.Command.Builtin.Help
  alias Tilde.Core.{Session, Suggest}
  alias Tilde.Core.Suggest.Item
  alias Tilde.Session.Registry

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
      known_sessions()
      |> Enum.filter(fn {id, _session} -> String.starts_with?(id, query) end)
      |> Enum.map(&session_item/1)

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

  defp known_sessions do
    Registry.sessions()
    |> Enum.map(&{&1.id, &1})
    |> Enum.uniq_by(fn {id, _session} -> id end)
    |> Enum.sort_by(fn {id, _session} -> id end)
  end

  defp session_item({id, session}) do
    preview = session_preview(session)

    Item.new(
      id: id,
      label: id,
      insert: "/attach #{id}",
      description: preview.row,
      detail: preview.detail,
      metadata: %{kind: :session, first: preview.first, last: preview.last}
    )
  end

  defp session_preview(nil),
    do: Preview.new(row: "no messages yet", detail: "No messages yet")

  defp session_preview(%Session{} = session) do
    messages =
      session.transcript.blocks
      |> Enum.filter(&message_preview?/1)
      |> Enum.map(& &1.source)

    case messages do
      [] ->
        session_preview(nil)

      [only] ->
        text = excerpt(only, 36)
        Preview.new(first: text, row: text, detail: "Message: #{excerpt(only, 120)}")

      many ->
        first_source = List.first(many)
        last_source = List.last(many)
        first = excerpt(first_source, 32)
        last = excerpt(last_source, 32)

        Preview.new(
          first: first,
          last: last,
          row: "#{first} → #{last}",
          detail: "First: #{excerpt(first_source, 120)}\nLast: #{excerpt(last_source, 120)}"
        )
    end
  end

  defp message_preview?(block),
    do: block.kind == :message and is_binary(block.source) and String.trim(block.source) != ""

  defp excerpt(text, max) do
    text =
      text
      |> to_string()
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    graphemes = String.graphemes(text)

    if length(graphemes) > max do
      graphemes |> Enum.take(max) |> Enum.join() |> Kernel.<>("…")
    else
      text
    end
  end
end
