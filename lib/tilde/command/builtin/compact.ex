defmodule Tilde.Command.Builtin.Compact do
  @moduledoc false

  @behaviour Tilde.Command.Behaviour

  alias Tilde.Command
  alias Tilde.Core.Session
  alias Tilde.Runtime.LLM
  alias Tilde.Session.Compaction

  def spec,
    do: Command.Spec.new("/compact", "/compact", "Summarize older context")

  def run(%Command{args: args}, %Session{} = session, opts) do
    case Compaction.prepare(session, summarizer: compaction_summarizer(args, opts)) do
      {:ok, result} ->
        metadata = %{
          first_kept_block_id: result.first_kept_block_id,
          tokens_before: result.tokens_before,
          compacted_blocks: result.compacted_blocks,
          custom_instructions: blank_to_nil(args)
        }

        [
          Command.Effect.AppendEvent.new(
            Tilde.context_compacted(result.summary, metadata: reject_nil_values(metadata))
          )
        ]

      {:error, :nothing_to_compact} ->
        [Command.Effect.AppendEvent.new(Tilde.assistant_done("Nothing to compact yet."))]
    end
  end

  defp compaction_summarizer(instructions, opts) do
    case Keyword.get(opts, :compaction_summarizer) do
      summarizer when is_function(summarizer, 2) ->
        fn blocks -> summarizer.(blocks, instructions: blank_to_nil(instructions)) end

      summarizer when is_function(summarizer, 1) ->
        summarizer

      _other ->
        fn blocks -> summarize_with_model(blocks, instructions) end
    end
  end

  defp summarize_with_model(blocks, instructions) do
    LLM.summarize_compaction(blocks, instructions: blank_to_nil(instructions))
  end

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp reject_nil_values(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
