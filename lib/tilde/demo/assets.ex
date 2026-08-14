defmodule Tilde.Demo.Assets do
  @moduledoc false

  @spec stylesheet_path() :: String.t()
  def stylesheet_path, do: "/assets/css/app.css"

  @spec javascript_path() :: String.t()
  def javascript_path do
    if Application.get_env(:tilde, :demo_code_reloader, true) do
      "/assets/js/app.ts"
    else
      "/assets/js/app.js"
    end
  end
end
