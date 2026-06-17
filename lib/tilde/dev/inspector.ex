defmodule Tilde.Dev.Inspector do
  @moduledoc "Raw terminal-style inspection text for devtools panels."

  alias Tilde.Core.Session

  @spec session(Session.t() | nil) :: String.t()
  def session(nil), do: "nil"

  def session(%Session{} = session) do
    inspect(session,
      pretty: true,
      limit: :infinity,
      printable_limit: :infinity,
      width: 100
    )
  end
end
