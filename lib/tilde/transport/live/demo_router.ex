defmodule Tilde.Transport.Live.DemoRouter do
  @moduledoc """
  Router for the standalone mirrored Tilde demo.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Tilde.Transport.Live.DemoLayout, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :demo_auth do
    plug(Tilde.Transport.Live.DemoAuth, :require_authenticated)
  end

  scope "/" do
    pipe_through(:browser)

    get("/login", Tilde.Transport.Live.DemoAuth, :new)
    post("/login", Tilde.Transport.Live.DemoAuth, :create)
    delete("/login", Tilde.Transport.Live.DemoAuth, :delete)
  end

  scope "/" do
    pipe_through([:browser, :demo_auth])

    live("/", Tilde.Transport.Live.Demo, :index)
    live("/tilde", Tilde.Transport.Live.Demo, :index)
    live("/tilde/:session_id", Tilde.Transport.Live.Demo, :index)
  end
end
