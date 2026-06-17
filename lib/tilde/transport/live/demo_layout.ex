defmodule Tilde.Transport.Live.DemoLayout do
  @moduledoc """
  Root layout for `Tilde.Transport.Live.DemoEndpoint`.
  """

  use Phoenix.Component

  def root(assigns) do
    assigns = assign(assigns, :live_socket_js, live_socket_js())

    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Tilde demo</title>
      </head>
      <body>
        {@inner_content}
        <script src="/assets/phoenix/phoenix.min.js">
        </script>
        <script src="/assets/live_view/phoenix_live_view.min.js">
        </script>
        {Phoenix.HTML.raw("<script>" <> @live_socket_js <> "</script>")}
      </body>
    </html>
    """
  end

  defp live_socket_js do
    hooks =
      String.replace(
        Tilde.Transport.Live.Hooks.js(),
        "export const TildeHooks",
        "const TildeHooks"
      )

    """
    #{hooks}

    const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket, {
      hooks: TildeHooks,
      params: { _csrf_token: csrfToken }
    })

    liveSocket.connect()
    window.liveSocket = liveSocket
    """
  end
end
