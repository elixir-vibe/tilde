defmodule Tilde.Demo.Auth do
  @moduledoc """
  Minimal session-backed authentication for the public Tilde demo.
  """

  use Phoenix.Controller, formats: [:html]

  import Plug.Conn

  @session_key :tilde_demo_authenticated

  @doc "Requires a successful demo login before continuing."
  def require_authenticated(conn, _opts) do
    if authenticated?(conn) do
      conn
    else
      conn
      |> put_resp_header("www-authenticate", ~s(Demo realm="tilde"))
      |> redirect(to: login_path(conn))
      |> halt()
    end
  end

  def new(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> html(login_page(error: false, return_to: return_to(conn)))
  end

  def create(conn, %{"password" => password} = params) do
    if Tilde.Demo.Password.valid?(password) do
      conn
      |> configure_session(renew: true)
      |> put_session(@session_key, true)
      |> redirect(to: safe_return_to(params["return_to"]))
    else
      conn
      |> put_status(:unauthorized)
      |> put_resp_header("cache-control", "no-store")
      |> html(login_page(error: true, return_to: safe_return_to(params["return_to"])))
    end
  end

  def create(conn, params), do: create(conn, Map.put(params, "password", ""))

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/login")
  end

  defp authenticated?(conn), do: get_session(conn, @session_key) == true

  defp return_to(conn), do: conn.params["return_to"] || current_request_path(conn)

  defp login_path(conn),
    do: "/login?return_to=" <> URI.encode_www_form(current_request_path(conn))

  defp current_request_path(conn) do
    path = conn.request_path
    query = conn.query_string
    if query == "", do: path, else: path <> "?" <> query
  end

  defp safe_return_to(nil), do: "/"
  defp safe_return_to(""), do: "/"
  defp safe_return_to("//" <> _), do: "/"
  defp safe_return_to("/login" <> _), do: "/"
  defp safe_return_to("/sessions/" <> _ = path), do: path
  defp safe_return_to("/"), do: "/"
  defp safe_return_to(_path), do: "/"

  defp login_page(opts) do
    error? = Keyword.fetch!(opts, :error)
    return_to = Keyword.fetch!(opts, :return_to)

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Tilde demo login</title>
        <link rel="stylesheet" href="#{app_css()}" />
      </head>
      <body>
        <main class="tilde auth">
          <section id="login-dialog" class="dialog" role="dialog" aria-modal="true" aria-labelledby="login-dialog-title">
            <div id="login-dialog-title" class="title"># tilde</div>
            <div class="body">
              <p>Enter the demo password to open the web console.</p>
              #{if error?, do: ~s(<p class="error">Incorrect password.</p>), else: ""}
              <form method="post" action="/login">
                <input type="hidden" name="_csrf_token" value="#{csrf_token()}" />
                <input type="hidden" name="return_to" value="#{escape(return_to)}" />
                <label for="password">Password</label>
                <input id="password" name="password" type="password" autofocus autocomplete="current-password" />
                <div class="actions">
                  <button type="submit" class="action primary">Enter</button>
                </div>
              </form>
            </div>
          </section>
        </main>
      </body>
    </html>
    """
  end

  defp app_css do
    Volt.static_path(Tilde.Demo.Endpoint, "/assets/css/app.css")
  rescue
    RuntimeError -> "/assets/css/app.css"
  end

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()

  defp escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
