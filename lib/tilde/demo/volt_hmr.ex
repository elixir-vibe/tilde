defmodule Tilde.Demo.VoltHMR do
  @moduledoc """
  Hosts Volt's HMR websocket with a longer idle timeout for the public demo.

  Volt's development server currently upgrades `/@volt/ws` with a 60-second
  idle timeout while the browser HMR client does not send heartbeats. On quiet
  pages that produces a once-per-minute disconnect/reconnect loop. Keep the
  same Volt HMR socket and route, but make the idle timeout long enough for a
  demo session.
  """

  @behaviour Plug

  alias Plug.Conn

  @idle_timeout :timer.hours(12)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Conn{request_path: "/@volt/ws"} = conn, _opts) do
    conn
    |> WebSockAdapter.upgrade(Volt.HMR.Socket, [], timeout: @idle_timeout)
    |> Conn.halt()
  end

  def call(conn, _opts), do: conn
end
