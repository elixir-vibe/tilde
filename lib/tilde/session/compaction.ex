defmodule Tilde.Session.Compaction do
  @moduledoc "Pi-style semantic context compaction for Tilde sessions."

  alias Tilde.Core.{Block, Event, Session}

  @default_keep_recent_messages 8
  @summary_heading "## Context Compaction"
  @summarizer_errors [
    RuntimeError,
    ArgumentError,
    FunctionClauseError,
    MatchError,
    KeyError,
    Protocol.UndefinedError,
    UndefinedFunctionError
  ]

  @type result :: %{
          summary: String.t(),
          first_kept_block_id: String.t(),
          tokens_before: non_neg_integer(),
          compacted_blocks: non_neg_integer()
        }

  @doc "Returns a compaction result for older message context without mutating the session."
  @spec prepare(Session.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def prepare(%Session{} = session, opts \\ []) do
    messages = context_message_blocks(session)
    keep_recent = Keyword.get(opts, :keep_recent_messages, @default_keep_recent_messages)

    message_count = Enum.count(messages)

    cond do
      message_count < 2 ->
        {:error, :nothing_to_compact}

      message_count <= keep_recent ->
        {:error, :nothing_to_compact}

      true ->
        {to_summarize, to_keep} = Enum.split(messages, message_count - keep_recent)

        case to_keep do
          [%Block{id: first_kept_id} | _rest] ->
            {:ok,
             %{
               summary: summarize(to_summarize, opts),
               first_kept_block_id: first_kept_id,
               tokens_before: estimate_tokens(messages),
               compacted_blocks: length(to_summarize)
             }}

          [] ->
            {:error, :nothing_to_compact}
        end
    end
  end

  @doc "Returns the latest compaction event in the session, if any."
  @spec latest_event(Session.t()) :: Event.t() | nil
  def latest_event(%Session{} = session) do
    session
    |> Session.events()
    |> Enum.reverse()
    |> Enum.find(&(&1.type == :context_compacted))
  end

  @doc "Returns message blocks to use for model context after semantic compaction."
  @spec model_context_blocks(Session.t()) :: [Block.t()]
  def model_context_blocks(%Session{} = session) do
    blocks = context_message_blocks(session)

    case latest_event(session) do
      %Event{text: summary, metadata: metadata} when is_binary(summary) ->
        tail = kept_tail(blocks, Map.get(metadata, :first_kept_block_id))
        [compaction_block(summary) | tail]

      _event ->
        blocks
    end
  end

  defp context_message_blocks(%Session{} = session) do
    Enum.filter(session.transcript.blocks, fn
      %Block{kind: :message, role: role, source: source, metadata: metadata}
      when role in [:user, :assistant] and is_binary(source) ->
        Map.get(metadata, :type) != :context_compaction

      _block ->
        false
    end)
  end

  defp kept_tail(blocks, nil), do: blocks

  defp kept_tail(blocks, first_kept_id) do
    case Enum.split_while(blocks, &(&1.id != first_kept_id)) do
      {_dropped, []} -> blocks
      {_dropped, kept} -> kept
    end
  end

  defp compaction_block(summary) do
    Block.message("context_compaction_summary", :system, summary,
      metadata: %{type: :context_compaction}
    )
  end

  @doc "Returns the deterministic extractive summary used when no model summary is available."
  @spec extractive_summary([Block.t()]) :: String.t()
  def extractive_summary(blocks) when is_list(blocks) do
    ([@summary_heading, "", "Earlier conversation was compacted into this checkpoint:", ""] ++
       (blocks
        |> Enum.map(&summary_line/1)
        |> reject_blank_lines()))
    |> Enum.join("\n")
  end

  defp summarize(blocks, opts) do
    case Keyword.get(opts, :summarizer) do
      summarizer when is_function(summarizer, 1) ->
        case summarizer.(blocks) do
          {:ok, summary} when is_binary(summary) -> blank_fallback(summary, blocks)
          summary when is_binary(summary) -> blank_fallback(summary, blocks)
          _other -> extractive_summary(blocks)
        end

      _other ->
        extractive_summary(blocks)
    end
  rescue
    _exception in @summarizer_errors -> extractive_summary(blocks)
  end

  defp blank_fallback(summary, blocks) do
    summary = String.trim(summary)
    if summary == "", do: extractive_summary(blocks), else: summary
  end

  defp summary_line(%Block{role: :user, source: source}) do
    "- User: #{shorten(source)}"
  end

  defp summary_line(%Block{role: :assistant, source: source}) do
    "- Assistant: #{shorten(source)}"
  end

  defp reject_blank_lines(lines), do: Enum.reject(lines, &(&1 == ""))

  defp shorten(text, max \\ 360) do
    text = String.trim(text)

    if String.length(text) <= max do
      text
    else
      text |> String.slice(0, max) |> String.trim_trailing() |> Kernel.<>("…")
    end
  end

  defp estimate_tokens(blocks) do
    Enum.sum_by(blocks, fn %Block{source: source} -> ceil(String.length(source || "") / 4) end)
  end
end
