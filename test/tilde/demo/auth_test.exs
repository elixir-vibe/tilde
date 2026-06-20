defmodule Tilde.Demo.AuthTest do
  use TildeTest.Case

  test "web demo requires password session" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :get
        |> conn("/")
        |> init_test_session(%{})
        |> Tilde.Demo.Router.call([])

      assert conn.status == 302
      assert [location] = Plug.Conn.get_resp_header(conn, "location")
      assert location =~ "/login?return_to=%2F"
    end)
  end

  test "web demo login accepts configured password" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Demo.Auth.create(%{
          "password" => "secret",
          "return_to" => "/sessions/auth-smoke"
        })

      assert conn.status == 302
      assert Plug.Conn.get_session(conn, :tilde_demo_authenticated) == true
      assert Plug.Conn.get_resp_header(conn, "location") == ["/sessions/auth-smoke"]
    end)
  end

  test "web demo login rejects protocol-relative return paths" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Demo.Auth.create(%{
          "password" => "secret",
          "return_to" => "//evil.example/path"
        })

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/"]
    end)
  end

  test "web demo login rejects wrong password" do
    with_application_env(:demo_password, "secret", fn ->
      conn =
        :post
        |> conn("/login")
        |> init_test_session(%{})
        |> Tilde.Demo.Auth.create(%{"password" => "wrong", "return_to" => "/"})

      assert conn.status == 401
      refute Plug.Conn.get_session(conn, :tilde_demo_authenticated)
      assert conn.resp_body =~ "Incorrect password"
    end)
  end
end
