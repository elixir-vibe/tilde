defmodule Tilde.Command.Effect do
  @moduledoc "Semantic effects emitted by slash commands."

  alias Tilde.Command.Effect.{AppendEvent, NewSession, ReplaceSession}

  @type t :: :ok | AppendEvent.t() | NewSession.t() | ReplaceSession.t()
end

defmodule Tilde.Command.Effect.AppendEvent do
  @moduledoc "Append an event to the current session."

  @type t :: %__MODULE__{event: Tilde.Core.Event.t()}
  defstruct [:event]

  @spec new(Tilde.Core.Event.t()) :: t()
  def new(event), do: %__MODULE__{event: event}
end

defmodule Tilde.Command.Effect.ReplaceSession do
  @moduledoc "Replace the current session with another session."

  @type t :: %__MODULE__{session: Tilde.Core.Session.t()}
  defstruct [:session]

  @spec new(Tilde.Core.Session.t()) :: t()
  def new(session), do: %__MODULE__{session: session}
end

defmodule Tilde.Command.Effect.NewSession do
  @moduledoc "Navigate to a new named session."

  @type t :: %__MODULE__{id: String.t()}
  defstruct [:id]

  @spec new(String.t()) :: t()
  def new(id), do: %__MODULE__{id: id}
end
