defmodule Tilde.Demo.Layout do
  @moduledoc """
  Root layout for `Tilde.Demo.Endpoint`.
  """

  use Phoenix.Component

  def root(assigns) do
    assigns =
      assigns
      |> assign(:app_css, Tilde.Demo.Assets.stylesheet_path())
      |> assign(:app_js, Tilde.Demo.Assets.javascript_path())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Tilde demo</title>
        <link phx-track-static rel="stylesheet" href={@app_css} />
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix/phoenix.min.js">
        </script>
        <script src="/assets/live_view/phoenix_live_view.min.js">
        </script>
        <script defer phx-track-static type="module" src={@app_js}>
        </script>
      </body>
    </html>
    """
  end
end
