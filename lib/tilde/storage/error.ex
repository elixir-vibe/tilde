defmodule Tilde.Storage.Error do
  @moduledoc "Raised when a configured storage adapter cannot complete a write."

  defexception [:operation, :reason]

  @type t :: %__MODULE__{operation: atom(), reason: term()}

  @impl true
  def message(%__MODULE__{operation: operation, reason: reason}) do
    "Tilde storage #{operation} failed: #{inspect(reason)}"
  end
end
