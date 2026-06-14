defmodule Tilde.Live.DemoAuth do
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
    if Plug.Crypto.secure_compare(password, password()) do
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

  defp password do
    Application.get_env(:tilde, :demo_password, "tilde")
  end

  defp return_to(conn), do: conn.params["return_to"] || current_request_path(conn)

  defp login_path(conn),
    do: "/login?return_to=" <> URI.encode_www_form(current_request_path(conn))

  defp current_request_path(conn) do
    path = conn.request_path
    query = conn.query_string
    if query == "", do: path, else: path <> "?" <> query
  end

  defp safe_return_to(nil), do: "/tilde"
  defp safe_return_to(""), do: "/tilde"
  defp safe_return_to("/login" <> _), do: "/tilde"
  defp safe_return_to("/" <> _ = path), do: path
  defp safe_return_to(_path), do: "/tilde"

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
        <style>
          :root { color-scheme: dark; }
          body {
            margin: 0;
            min-height: 100dvh;
            display: grid;
            place-items: center;
            background: #080a0f;
            color: #e8edf2;
            font: 15px/1.5 ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
          }
          main {
            width: min(38rem, calc(100vw - 2rem));
            border: 1px solid #283241;
            background: #10141d;
            box-shadow: 0 24px 80px rgb(0 0 0 / 0.35);
            padding: 1.25rem;
          }
          h1 { margin: 0 0 0.75rem; font-size: 1rem; color: #ffffff; }
          p { margin: 0 0 1rem; color: #9ba7b4; }
          label { display: block; margin-bottom: 0.5rem; color: #cbd5df; }
          input {
            box-sizing: border-box;
            width: 100%;
            border: 1px solid #344153;
            background: #080a0f;
            color: #ffffff;
            padding: 0.7rem 0.8rem;
            font: inherit;
          }
          button {
            margin-top: 1rem;
            border: 1px solid #61708a;
            background: #e8edf2;
            color: #080a0f;
            padding: 0.65rem 0.9rem;
            font: inherit;
            cursor: pointer;
          }
          .error { color: #ff9b9b; }
        </style>
      </head>
      <body>
        <main>
          <h1># tilde</h1>
          <p>Enter the demo password to open the web console.</p>
          #{if error?, do: ~s(<p class="error">Incorrect password.</p>), else: ""}
          <form method="post" action="/login">
            <input type="hidden" name="_csrf_token" value="#{csrf_token()}" />
            <input type="hidden" name="return_to" value="#{escape(return_to)}" />
            <label for="password">Password</label>
            <input id="password" name="password" type="password" autofocus autocomplete="current-password" />
            <button type="submit">Enter</button>
          </form>
        </main>
      </body>
    </html>
    """
  end

  defp csrf_token, do: Plug.CSRFProtection.get_csrf_token()

  defp escape(value) do
    value
    |> to_string()
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
  end
end
