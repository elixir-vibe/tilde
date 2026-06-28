defmodule Tilde.Core.AssistantTurn do
  @moduledoc """
  Strict assistant-turn lifecycle state for UI/runtime coordination.

  ReqLLM owns provider-normalized payload structs such as `ReqLLM.StreamChunk`,
  `ReqLLM.Response`, and `ReqLLM.Message.ContentPart`. Tilde owns the UI/runtime
  lifecycle around those payloads: waiting for the first chunk, streaming,
  tool-calling, completion, cancellation, and errors.
  """

  alias ReqLLM.{Response, StreamChunk, ToolCall}

  @type phase ::
          :idle | :waiting | :streaming | :thinking | :tooling | :done | :error | :cancelled

  @type t :: %__MODULE__{
          id: String.t() | nil,
          block_id: String.t() | nil,
          phase: phase(),
          chunks: [StreamChunk.t()],
          tool_calls: [ToolCall.t() | StreamChunk.t() | map()],
          response: Response.t() | nil,
          usage: map() | nil,
          error: term()
        }

  defstruct id: nil,
            block_id: nil,
            phase: :idle,
            chunks: [],
            tool_calls: [],
            response: nil,
            usage: nil,
            error: nil

  @doc "Creates an idle assistant turn."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id),
      block_id: Keyword.get(opts, :block_id),
      phase: Keyword.get(opts, :phase, :idle),
      chunks: Keyword.get(opts, :chunks, []),
      tool_calls: Keyword.get(opts, :tool_calls, []),
      response: Keyword.get(opts, :response),
      usage: Keyword.get(opts, :usage),
      error: Keyword.get(opts, :error)
    }
  end

  @doc "Starts a turn that is waiting for first model output."
  @spec waiting(String.t() | nil, keyword()) :: t()
  def waiting(block_id, opts \\ []) do
    opts
    |> Keyword.put(:block_id, block_id)
    |> Keyword.put(:phase, :waiting)
    |> new()
  end

  @doc "Applies a normalized ReqLLM stream chunk to the lifecycle state."
  @spec apply_chunk(t(), StreamChunk.t()) :: t()
  def apply_chunk(%__MODULE__{} = turn, %StreamChunk{type: :content} = chunk) do
    %{append_chunk(turn, chunk) | phase: :streaming}
  end

  def apply_chunk(%__MODULE__{} = turn, %StreamChunk{type: :thinking} = chunk) do
    %{append_chunk(turn, chunk) | phase: :thinking}
  end

  def apply_chunk(%__MODULE__{} = turn, %StreamChunk{type: :tool_call} = chunk) do
    turn
    |> append_chunk(chunk)
    |> Map.update!(:tool_calls, &[chunk | &1])
    |> Map.put(:phase, :tooling)
  end

  def apply_chunk(%__MODULE__{} = turn, %StreamChunk{} = chunk), do: append_chunk(turn, chunk)

  @doc "Marks the turn done."
  @spec done(t(), Response.t() | nil) :: t()
  def done(%__MODULE__{} = turn, response \\ nil) do
    %{turn | phase: :done, response: response, usage: usage(response), error: nil}
  end

  @doc "Marks the turn failed."
  @spec error(t(), term()) :: t()
  def error(%__MODULE__{} = turn, reason), do: %{turn | phase: :error, error: reason}

  @doc "Marks the turn cancelled."
  @spec cancelled(t()) :: t()
  def cancelled(%__MODULE__{} = turn), do: %{turn | phase: :cancelled}

  @doc "Returns true while a placeholder should be visible."
  @spec waiting?(t()) :: boolean()
  def waiting?(%__MODULE__{phase: :waiting}), do: true
  def waiting?(_turn), do: false

  @doc "Returns true while model/tool output is still active."
  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{phase: phase}), do: phase in [:waiting, :streaming, :thinking, :tooling]

  @doc "Returns true once visible assistant content has started."
  @spec content_started?(t()) :: boolean()
  def content_started?(%__MODULE__{phase: phase}),
    do: phase in [:streaming, :thinking, :tooling, :done]

  @doc "Returns assistant chunks in chronological order."
  @spec chunks(t()) :: [StreamChunk.t()]
  def chunks(%__MODULE__{chunks: chunks}), do: Enum.reverse(chunks)

  defp append_chunk(%__MODULE__{} = turn, %StreamChunk{} = chunk) do
    %{turn | chunks: [chunk | turn.chunks]}
  end

  defp usage(%Response{usage: usage}), do: usage
  defp usage(_response), do: nil
end
