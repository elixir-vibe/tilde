defmodule Tilde.Live.DemoRouter do
  @moduledoc """
  Router for the standalone mirrored Tilde demo.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Tilde.Live.DemoLayout, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :demo_auth do
    plug(Tilde.Live.DemoAuth, :require_authenticated)
  end

  scope "/" do
    pipe_through(:browser)

    get("/login", Tilde.Live.DemoAuth, :new)
    post("/login", Tilde.Live.DemoAuth, :create)
    delete("/login", Tilde.Live.DemoAuth, :delete)
  end

  scope "/" do
    pipe_through([:browser, :demo_auth])

    live("/", Tilde.Live.Demo, :index)
    live("/tilde", Tilde.Live.Demo, :index)
    live("/tilde/:session_id", Tilde.Live.Demo, :index)
  end
end
