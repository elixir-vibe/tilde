defmodule Tilde.Demo.Endpoint do
  @moduledoc """
  Minimal Phoenix endpoint for the mirrored Tilde demo.

  It is not started by the package application. Use `mix tilde.demo` to run this
  endpoint together with `Tilde.Transport.SSH.Demo` against the same `Tilde.Session.Server`.
  """

  use Phoenix.Endpoint, otp_app: :tilde

  @session_options [
    store: :cookie,
    key: "_tilde_demo_key",
    signing_salt: "tilde_demo_session"
  ]

  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false
  )

  if Code.ensure_loaded?(Phoenix.LiveReloader.Socket) do
    socket("/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket)
  end

  plug(Plug.Static,
    at: "/assets/phoenix",
    from: {:phoenix, "priv/static"},
    only: ~w(phoenix.min.js)
  )

  plug(Plug.Static,
    at: "/assets/live_view",
    from: {:phoenix_live_view, "priv/static"},
    only: ~w(phoenix_live_view.min.js)
  )

  if Code.ensure_loaded?(Phoenix.LiveReloader) do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.LiveReloader)
  end

  plug(Tilde.Demo.VoltHMR)
  plug(Volt.DevServer, root: "assets")

  plug(Plug.Static,
    at: "/assets",
    from: "priv/static/assets",
    gzip: false
  )

  plug(Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["*/*"]
  )

  plug(Plug.Session, @session_options)
  plug(Tilde.Demo.Router)
end
