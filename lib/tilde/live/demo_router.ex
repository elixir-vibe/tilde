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

  scope "/" do
    pipe_through(:browser)

    live("/", Tilde.Live.Demo, :index)
    live("/tilde", Tilde.Live.Demo, :index)
    live("/tilde/:session_id", Tilde.Live.Demo, :index)
  end
end
