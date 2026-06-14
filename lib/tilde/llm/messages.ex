defmodule Tilde.LLM.Messages do
  @moduledoc """
  Projects Tilde's semantic transcript into LLM conversation messages.

  The Tilde session remains the source of truth. This module is only an adapter
  from semantic message blocks to provider/runtime conversation context.
  """

  alias Tilde.{Block, Session}

  @type message :: %{role: :user | :assistant, content: String.t()}

  @doc "Projects user/assistant message blocks to chronological LLM messages."
  @spec to_messages(Session.t(), keyword()) :: [message()]
  def to_messages(%Session{} = session, opts \\ []) do
    blocks = session.transcript.blocks

    blocks =
      if Keyword.get(opts, :exclude_latest_user, false) do
        drop_latest_user_message(blocks)
      else
        blocks
      end

    blocks
    |> Enum.flat_map(&message_block_to_messages/1)
  end

  @doc "Projects semantic messages into `Jido.AI.Context` when Jido.AI is available."
  @spec to_jido_context(Session.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def to_jido_context(%Session{} = session, opts \\ []) do
    if Code.ensure_loaded?(Jido.AI.Context) do
      context =
        Jido.AI.Context.new()
        |> Jido.AI.Context.append_messages(to_messages(session, opts))

      {:ok, context}
    else
      {:error, :jido_ai_context_not_available}
    end
  end

  defp message_block_to_messages(%Block{kind: :message, role: :user, source: source})
       when is_binary(source) do
    [%{role: :user, content: source}]
  end

  defp message_block_to_messages(%Block{kind: :message, role: :assistant, source: source})
       when is_binary(source) do
    [%{role: :assistant, content: source}]
  end

  defp message_block_to_messages(_block), do: []

  defp drop_latest_user_message(blocks) do
    {reversed, dropped?} =
      blocks
      |> Enum.reverse()
      |> Enum.reduce({[], false}, fn
        %Block{kind: :message, role: :user}, {acc, false} -> {acc, true}
        block, {acc, dropped?} -> {[block | acc], dropped?}
      end)

    if dropped?, do: reversed, else: blocks
  end
end
