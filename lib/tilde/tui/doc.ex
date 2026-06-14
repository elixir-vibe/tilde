defmodule Tilde.TUI.Doc do
  @moduledoc """
  Width-aware terminal layout documents for Tilde sessions.

  This module uses `Inspect.Algebra` as a renderer-local layout IR. The algebra
  document is not durable state; it is derived from semantic Tilde blocks.
  """

  import Inspect.Algebra, only: [concat: 2, empty: 0]

  alias Tilde.{Block, Session, Suggest, ToolView, Transcript}
  alias Tilde.TUI.Theme

  @doc "Builds an algebra document for a session."
  @spec session(Session.t(), keyword()) :: Inspect.Algebra.t()
  def session(%Session{} = session, opts \\ []) do
    [
      header(opts),
      transcript(session.transcript, opts),
      widgets(session, opts),
      input_prompt(session, opts),
      footer(session, opts)
    ]
    |> Enum.reject(&empty_doc?/1)
    |> join_docs(blank_line())
  end

  @doc "Builds an algebra document for a transcript."
  @spec transcript(Transcript.t(), keyword()) :: Inspect.Algebra.t()
  def transcript(%Transcript{} = transcript, opts \\ []) do
    transcript.blocks
    |> Enum.map(&block(&1, opts))
    |> join_docs(blank_line())
  end

  @doc "Builds an algebra document for a block."
  @spec block(Block.t(), keyword()) :: Inspect.Algebra.t()
  def block(block, opts \\ [])

  def block(%Block{kind: :message} = block, opts) do
    concat([
      Theme.muted(to_string(block.role), opts),
      newline(),
      text_doc(message_text(block), indent: 2)
    ])
  end

  def block(%Block{kind: :tool} = block, opts) do
    view = ToolView.view(block)

    concat([
      tool_header(view, opts),
      metadata_rows(view.metadata_rows, opts),
      stream_docs(view.streams, opts),
      hidden_doc(view, opts)
    ])
  end

  def block(%Block{kind: :choice, choice: choice}, opts) do
    options =
      choice.options
      |> Enum.map(fn option ->
        marker = if option.id in choice.selected, do: "[x]", else: "[ ]"

        concat([
          "  ",
          Theme.accent(marker, opts),
          " ",
          option.label,
          option_description(option, opts)
        ])
      end)
      |> join_docs(newline())

    concat([Theme.title(choice.question, opts), newline(), options])
  end

  def block(%Block{kind: kind}, opts), do: Theme.muted("#{kind}", opts)

  defp header(opts), do: Theme.title("# tilde", opts)

  defp footer(%Session{} = session, opts) do
    status = Enum.map_join(session.statuses, " · ", fn {key, value} -> "#{key}: #{value}" end)
    if status == "", do: empty(), else: Theme.muted(status, opts)
  end

  defp input_prompt(%Session{} = session, opts) do
    value = session.input.value
    cursor = min(session.input.cursor, String.length(value))
    {left, right} = value |> String.graphemes() |> Enum.split(cursor)

    concat([
      Theme.accent(">", opts),
      " ",
      Enum.join(left),
      Theme.muted("▌", opts),
      Enum.join(right)
    ])
  end

  defp widgets(%Session{} = session, opts) do
    session.widgets
    |> Enum.flat_map(fn {_placement, widgets} -> widgets end)
    |> Enum.map(&widget_doc(&1, opts))
    |> join_docs(newline())
  end

  defp widget_doc(%{content: %Suggest{} = suggest}, opts) do
    rows =
      suggest.items
      |> Enum.map(fn item ->
        concat([
          "  ",
          Theme.accent(item.label, opts),
          String.duplicate(" ", max(1, 12 - String.length(item.label))),
          item.description
        ])
      end)
      |> join_docs(newline())

    concat([Theme.muted(suggest.title, opts), newline(), rows])
  end

  defp widget_doc(widget, opts), do: Theme.muted("#{widget.id}: #{inspect(widget.content)}", opts)

  defp tool_header(view, opts) do
    [
      Theme.title(view.name, opts),
      non_empty_doc(Theme.accent(view.arg_summary, opts)),
      Theme.muted(to_string(view.status), opts)
    ]
    |> Enum.reject(&empty_doc?/1)
    |> join_docs(" ")
  end

  defp metadata_rows([], _opts), do: empty()

  defp metadata_rows(rows, opts) do
    rows
    |> Enum.map(fn {key, value} -> concat([Theme.muted("#{key}:", opts), " ", value]) end)
    |> join_docs("  ")
    |> prefix_line()
  end

  defp stream_docs([], _opts), do: empty()

  defp stream_docs(streams, opts) do
    streams
    |> Enum.reject(fn stream -> stream.lines == [] and stream.hidden_lines == 0 end)
    |> Enum.map(&stream_doc(&1, length(streams), opts))
    |> join_docs(newline())
    |> prefix_line()
  end

  defp stream_doc(stream, stream_count, opts) do
    label =
      if stream_count > 1,
        do: concat([Theme.muted("#{stream.kind}", opts), newline()]),
        else: empty()

    body =
      stream.lines
      |> Enum.map(&stream_line(&1, stream.kind, opts))
      |> hidden_stream_lines(stream, opts)
      |> Enum.map(&concat(["  ", &1]))
      |> join_docs(newline())

    concat([label, body])
  end

  defp stream_line(line, :stderr, opts), do: Theme.error(line, opts)
  defp stream_line(line, :log, opts), do: Theme.muted(line, opts)
  defp stream_line(line, :result, opts), do: Theme.success(line, opts)
  defp stream_line(line, _kind, _opts), do: line

  defp hidden_stream_lines(lines, %{hidden_lines: 0}, _opts), do: lines

  defp hidden_stream_lines(lines, stream, opts) do
    lines ++ [Theme.muted("… #{stream.hidden_lines} more #{stream.kind} lines", opts)]
  end

  defp hidden_doc(%{hidden_lines: 0, expanded?: false}, _opts), do: empty()

  defp hidden_doc(%{hidden_lines: 0, expanded?: true}, opts),
    do: prefix_line(Theme.muted("(ctrl+o to collapse)", opts))

  defp hidden_doc(view, opts) do
    prefix_line(Theme.muted("… #{view.hidden_lines} more lines (ctrl+o to expand)", opts))
  end

  defp message_text(%Block{runs: [_ | _] = runs}), do: Enum.map_join(runs, & &1.text)
  defp message_text(%Block{source: source}), do: source

  defp option_description(%{description: description}, opts),
    do: Theme.muted(" — #{description}", opts)

  defp option_description(_option, _opts), do: ""

  defp text_doc(text, opts) do
    indent = String.duplicate(" ", Keyword.get(opts, :indent, 0))

    text
    |> String.trim_trailing()
    |> String.split("\n")
    |> Enum.map(&(indent <> &1))
    |> join_docs(newline())
  end

  defp blank_line, do: "\n\n"
  defp prefix_line(doc), do: concat([newline(), doc])
  defp newline, do: "\n"

  defp non_empty_doc(""), do: empty()
  defp non_empty_doc(doc), do: doc

  defp join_docs([], _separator), do: empty()
  defp join_docs([doc], _separator), do: doc

  defp join_docs([doc | rest], separator) do
    Enum.reduce(rest, doc, fn next, acc -> concat([acc, separator, next]) end)
  end

  defp concat(docs), do: Enum.reduce(docs, empty(), &concat(&2, &1))
  defp empty_doc?(doc), do: doc == empty()
end
