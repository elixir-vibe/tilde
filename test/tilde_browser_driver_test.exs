defmodule TildeBrowserDriverTest do
  use ExUnit.Case, async: false

  alias TildeTest.Driver.Browser

  @moduletag :browser

  test "PlaywrightEx browser driver can type slash suggestions with real JavaScript" do
    if Browser.available?() do
      state = Browser.open()

      try do
        state
        |> Browser.type("/")
        |> Browser.press(:down)
        |> Browser.press(:enter)

        assert Browser.text(state) =~ "/"
      after
        Browser.close(state)
      end
    else
      IO.puts("Skipping browser driver smoke test: playwright executable is not available")
      assert true
    end
  end
end
