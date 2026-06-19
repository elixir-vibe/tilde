defmodule Tilde.Dev.Inspector do
  @moduledoc "Raw terminal-style inspection text for devtools panels."

  alias Tilde.Core.Session

  @spec session(Session.t() | nil, map() | nil) :: String.t()
  def session(session, agent_loop \\ nil)

  def session(nil, nil), do: "nil"

  def session(%Session{} = session, nil) do
    inspect(session,
      pretty: true,
      limit: :infinity,
      printable_limit: :infinity,
      width: 100
    )
  end

  def session(%Session{} = session, agent_loop) when is_map(agent_loop) do
    inspect(%{session: session, agent_loop: agent_loop},
      pretty: true,
      limit: :infinity,
      printable_limit: :infinity,
      width: 100
    )
  end
end
