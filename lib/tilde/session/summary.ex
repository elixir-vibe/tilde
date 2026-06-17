defmodule Tilde.Session.Summary do
  @moduledoc "Bounded session summary for index and attach suggestions."

  alias Tilde.Core.Session
  alias Tilde.Core.Suggest.Item
  alias Tilde.Session.Registry
  alias Tilde.Storage

  @type t :: %__MODULE__{
          id: String.t(),
          first: String.t() | nil,
          last: String.t() | nil,
          row: String.t(),
          detail: String.t(),
          source: :live | :persisted
        }

  defstruct id: "", first: nil, last: nil, row: "", detail: "", source: :live

  @spec list() :: [t()]
  def list do
    live = Registry.sessions() |> Enum.map(&from_session/1)

    persisted =
      case Storage.session_summaries() do
        {:ok, summaries} -> summaries
        {:error, _reason} -> []
      end

    (persisted ++ live)
    |> Map.new(&{&1.id, &1})
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end

  @spec from_session(Session.t()) :: t()
  def from_session(%Session{} = session) do
    preview = preview(session)
    %__MODULE__{preview | id: session.id}
  end

  @spec to_suggest_item(t(), keyword()) :: Item.t()
  def to_suggest_item(%__MODULE__{} = summary, opts \\ []) do
    insert = Keyword.get(opts, :insert, summary.id)

    Item.new(
      id: summary.id,
      label: summary.id,
      insert: insert,
      description: summary.row,
      detail: summary.detail,
      metadata: %{
        kind: :session,
        session_id: summary.id,
        source: summary.source,
        first: summary.first,
        last: summary.last
      }
    )
  end

  @spec from_texts(String.t(), [String.t()], keyword()) :: t()
  def from_texts(id, texts, opts \\ []) when is_binary(id) and is_list(texts) do
    summary = preview_texts(texts)
    %{summary | id: id, source: Keyword.get(opts, :source, :persisted)}
  end

  defp preview(%Session{} = session) do
    session.transcript.blocks
    |> Enum.filter(&message_preview?/1)
    |> Enum.map(& &1.source)
    |> preview_texts()
  end

  defp preview_texts(messages) do
    case messages do
      [] ->
        %__MODULE__{row: "no messages yet", detail: "No messages yet"}

      [only] ->
        text = excerpt(only, 36)
        %__MODULE__{first: text, row: text, detail: "Message: #{excerpt(only, 120)}"}

      many ->
        first_source = List.first(many)
        last_source = List.last(many)
        first = excerpt(first_source, 32)
        last = excerpt(last_source, 32)

        %__MODULE__{
          first: first,
          last: last,
          row: "#{first} → #{last}",
          detail: "First: #{excerpt(first_source, 120)}\nLast: #{excerpt(last_source, 120)}"
        }
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
