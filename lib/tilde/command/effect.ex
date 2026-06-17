defmodule Tilde.Command.Effect do
  @moduledoc "Semantic effects emitted by slash commands."

  alias Tilde.Command.Effect.{
    AppendEvent,
    AttachSession,
    DetachSession,
    NewSession,
    ReplaceSession,
    ShowSessionInfo
  }

  @type t ::
          :ok
          | AppendEvent.t()
          | AttachSession.t()
          | DetachSession.t()
          | NewSession.t()
          | ReplaceSession.t()
          | ShowSessionInfo.t()
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

defmodule Tilde.Command.Effect.AttachSession do
  @moduledoc "Attach a transport to an existing named session."

  @type t :: %__MODULE__{id: String.t()}
  defstruct [:id]

  @spec new(String.t()) :: t()
  def new(id), do: %__MODULE__{id: id}
end

defmodule Tilde.Command.Effect.DetachSession do
  @moduledoc "Detach a transport to a private session."

  @type t :: %__MODULE__{}
  defstruct []

  @spec new() :: t()
  def new, do: %__MODULE__{}
end

defmodule Tilde.Command.Effect.ShowSessionInfo do
  @moduledoc "Ask a transport to show session routing information."

  @type t :: %__MODULE__{}
  defstruct []

  @spec new() :: t()
  def new, do: %__MODULE__{}
end
