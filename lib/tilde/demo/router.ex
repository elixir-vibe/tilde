defmodule Tilde.Demo.Router do
  @moduledoc """
  Router for the standalone mirrored Tilde demo.
  """

  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {Tilde.Demo.Layout, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :demo_auth do
    plug(Tilde.Demo.Auth, :require_authenticated)
  end

  scope "/" do
    pipe_through(:browser)

    get("/login", Tilde.Demo.Auth, :new)
    post("/login", Tilde.Demo.Auth, :create)
    delete("/login", Tilde.Demo.Auth, :delete)
  end

  scope "/" do
    pipe_through([:browser, :demo_auth])

    live("/", Tilde.Demo.Live, :index, as: :demo)
    live("/tilde", Tilde.Demo.Live, :index, as: :demo)
    live("/tilde/:session_id", Tilde.Demo.Live, :index, as: :demo)
  end
end
