defmodule Tilde.Storage.EventPolicy do
  @moduledoc "Storage policy for existing `Tilde.Core.Event` values."

  alias Tilde.Core.Event

  @doc "Returns true when an event belongs in the durable canonical event log."
  @spec persist?(Event.t()) :: boolean()
  def persist?(%Event{type: :input_changed}), do: false
  def persist?(%Event{}), do: true
end
