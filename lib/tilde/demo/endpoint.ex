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

  plug(Plug.Parsers,
    parsers: [:urlencoded],
    pass: ["*/*"]
  )

  plug(Plug.Session, @session_options)
  plug(Tilde.Demo.Router)
end
