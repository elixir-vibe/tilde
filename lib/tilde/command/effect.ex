defmodule Tilde.Command.Effect do
  @moduledoc "Semantic effects emitted by slash commands."

  alias Tilde.Core.Session

  @type t ::
          :ok
          | {:replace_session, Session.t()}
          | {:append_event, Tilde.Core.Event.t()}
          | {:new_session, String.t()}
end
