defmodule Tilde.Transport.SSH.Shell do
  @moduledoc """
  Minimal SSH shell loop for the Tilde demo.

  This is intentionally not a PTY emulator or OS shell. It uses SSH only as a
  terminal transport for the semantic Tilde session and TUI renderer.
  """

  alias Tilde.Core.{Controller, Keys, Session}
  alias Tilde.Renderer.TUI

  @doc "Starts the interactive demo shell. Called by Erlang SSH's shell option."
  @spec start(keyword()) :: :ok
  def start(opts \\ []) do
    width = Keyword.get(opts, :width, 100)
    session = Keyword.get_lazy(opts, :session, &Tilde.Demo.Live.demo_session/0)

    session
    |> render(width)
    |> loop(width)
  end

  @doc "Applies a decoded key to a session."
  @spec apply_key(Session.t(), Keys.key()) :: Controller.result()
  def apply_key(%Session{} = session, key), do: Controller.apply_key(session, key)

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
    |> TUI.render(width: width)
    |> IO.iodata_to_binary()
    |> IO.write()

    session
  end
end
