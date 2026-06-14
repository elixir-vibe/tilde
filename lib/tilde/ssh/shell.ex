defmodule Tilde.SSH.Shell do
  @moduledoc """
  Minimal SSH shell loop for the Tilde demo.

  This is intentionally not a PTY emulator or OS shell. It uses SSH only as a
  terminal transport for the semantic Tilde session and TUI renderer.
  """

  alias Tilde.{Block, Session}
  alias Tilde.TUI.{Keys, Renderer}

  @doc "Starts the interactive demo shell. Called by Erlang SSH's shell option."
  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    width = Keyword.get(opts, :width, 100)
    session = Keyword.get_lazy(opts, :session, &Tilde.Live.Demo.demo_session/0)

    session
    |> render(width)
    |> loop(width)
  end

  @doc "Applies a decoded key to a session."
  @spec apply_key(Session.t(), Keys.key()) :: {:cont, Session.t()} | {:halt, Session.t()}
  def apply_key(%Session{} = session, :toggle_expand) do
    case first_tool_id(session) do
      nil -> {:cont, session}
      id -> {:cont, Session.toggle_expand(session, id)}
    end
  end

  def apply_key(%Session{} = session, :quit), do: {:halt, session}
  def apply_key(%Session{} = session, :redraw), do: {:cont, session}
  def apply_key(%Session{} = session, _key), do: {:cont, session}

  defp loop(%Session{} = session, width) do
    case IO.getn("", 1) do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      data when is_binary(data) ->
        case apply_key(session, Keys.decode(data)) do
          {:cont, session} -> session |> render(width) |> loop(width)
          {:halt, _session} -> :ok
        end
    end
  end

  defp render(%Session{} = session, width) do
    session
    |> Renderer.render(width: width)
    |> IO.iodata_to_binary()
    |> IO.write()

    session
  end

  defp first_tool_id(%Session{} = session) do
    Enum.find_value(session.transcript.blocks, fn
      %Block{kind: :tool, id: id} -> id
      _block -> nil
    end)
  end
end
