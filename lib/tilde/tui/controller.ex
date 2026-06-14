defmodule Tilde.TUI.Controller do
  @moduledoc """
  Transport-independent TUI input controller.

  SSH, tests, and future terminal transports can decode bytes into
  `Tilde.TUI.Keys.key/0` values and apply them here.
  """

  alias Tilde.{Block, Session}
  alias Tilde.TUI.Keys

  @type result :: {:cont, Session.t()} | {:halt, Session.t()}

  @doc "Applies a decoded key to a session."
  @spec apply_key(Session.t(), Keys.key()) :: result()
  def apply_key(%Session{} = session, :toggle_expand) do
    case first_tool_id(session) do
      nil -> {:cont, session}
      id -> {:cont, Session.toggle_expand(session, id)}
    end
  end

  def apply_key(%Session{} = session, :quit), do: {:halt, session}
  def apply_key(%Session{} = session, :redraw), do: {:cont, session}
  def apply_key(%Session{} = session, _key), do: {:cont, session}

  defp first_tool_id(%Session{} = session) do
    Enum.find_value(session.transcript.blocks, fn
      %Block{kind: :tool, id: id} -> id
      _block -> nil
    end)
  end
end
