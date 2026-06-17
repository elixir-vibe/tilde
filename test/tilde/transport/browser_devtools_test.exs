defmodule Tilde.Transport.BrowserDevtoolsTest do
  use TildeTest.BrowserCase

  @moduletag :browser

  test "devtools grid and raw inspector toggle from the browser", %{browser: browser} do
    browser
    |> Browser.assert_has(".tilde .dev")
    |> Browser.assert_text("grid:off")
    |> Browser.assert_text("raw:off")
    |> Browser.click("button[phx-click='tilde:dev_toggle_grid']")
    |> Browser.assert_has(".tilde.grid")
    |> Browser.assert_text("grid:on")
    |> Browser.click("button[phx-click='tilde:dev_toggle_inspector']")
    |> Browser.assert_has(".tilde .inspect")
    |> Browser.assert_text("raw:on")
    |> Browser.assert_text("%Tilde.Core.Session{")
  end
end
