defmodule Tilde.Core.Event do
  @moduledoc """
  Append-only console event.

  Events are the durable source of truth. Transcript blocks, compact tool views,
  renderers, and LiveView assigns are derived from this log.
  """

  @type type ::
          :user_message
          | :assistant_turn_started
          | :assistant_delta
          | :assistant_done
          | :assistant_turn_finished
          | :assistant_turn_error
          | :assistant_turn_cancelled
          | :tool_started
          | :tool_stream
          | :tool_done
          | :block_display_changed
          | :input_changed
          | :input_submitted
          | :status_changed
          | :context_compacted

  @type t :: %__MODULE__{
          id: String.t(),
          type: type(),
          at: DateTime.t() | nil,
          block_id: String.t() | nil,
          tool_call_id: String.t() | nil,
          role: atom() | nil,
          text: term(),
          name: String.t() | nil,
          args: map(),
          stream: atom() | nil,
          chunk: String.t() | nil,
          status: atom() | nil,
          result: term(),
          display: map(),
          metadata: map()
        }

  defstruct id: nil,
            type: nil,
            at: nil,
            block_id: nil,
            tool_call_id: nil,
            role: nil,
            text: nil,
            name: nil,
            args: %{},
            stream: nil,
            chunk: nil,
            status: nil,
            result: nil,
            display: %{},
            metadata: %{}

  @doc "Builds an event with a generated id."
  @spec new(type(), keyword()) :: t()
  def new(type, attrs \\ []) do
    attrs = Map.new(attrs)

    struct!(__MODULE__,
      id: Map.get(attrs, :id, unique_id(type)),
      type: type,
      at: Map.get(attrs, :at),
      block_id: Map.get(attrs, :block_id),
      tool_call_id: Map.get(attrs, :tool_call_id),
      role: Map.get(attrs, :role),
      text: Map.get(attrs, :text),
      name: Map.get(attrs, :name),
      args: Map.get(attrs, :args, %{}),
      stream: Map.get(attrs, :stream),
      chunk: Map.get(attrs, :chunk),
      status: Map.get(attrs, :status),
      result: Map.get(attrs, :result),
      display: Map.get(attrs, :display, %{}),
      metadata: Map.get(attrs, :metadata, %{})
    )
  end

  defp unique_id(type) do
    suffix = System.unique_integer([:positive, :monotonic])
    "evt_#{type}_#{suffix}"
  end
end
