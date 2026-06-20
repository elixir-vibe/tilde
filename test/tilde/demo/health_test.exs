defmodule Tilde.Demo.HealthTest do
  use TildeTest.Case

  test "endpoint is unauthenticated" do
    conn =
      :get
      |> conn("/healthz")
      |> Tilde.Demo.Router.call([])

    assert conn.status == 200
    assert conn.resp_body == "ok"
  end
end
