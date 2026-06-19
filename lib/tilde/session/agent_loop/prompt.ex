defmodule Tilde.Session.AgentLoop.Prompt do
  @moduledoc "Runtime prompt queued for the session-owned agent loop."

  alias Tilde.Core.Event

  @enforce_keys [:index, :text]
  defstruct [:index, :text, :event_id]

  @type t :: %__MODULE__{
          index: pos_integer(),
          text: String.t(),
          event_id: String.t() | nil
        }

  @spec new(pos_integer(), Event.t()) :: t()
  def new(index, %Event{text: text, id: event_id}) when is_integer(index) and is_binary(text) do
    %__MODULE__{index: index, text: text, event_id: event_id}
  end
end
