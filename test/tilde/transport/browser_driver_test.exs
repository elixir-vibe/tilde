defmodule TildeBrowserDriverTest do
  use TildeTest.BrowserCase, async: false

  @moduletag :browser

  test "PlaywrightEx browser driver completes on tab and executes slash suggestions on enter", %{
    browser: browser
  } do
    if browser do
      browser
      |> Browser.type("/")
      |> Browser.press(:tab)

      browser
      |> Browser.assert_input("/help")
      |> Browser.press(:enter)
      |> Browser.assert_input("")
      |> Browser.refute_has(".suggest")
      |> Browser.assert_text("/new [name]")
    else
      skip_browser()
    end
  end

  test "real browser escape cancels slash suggestions without clearing input", %{browser: browser} do
    if browser do
      browser
      |> Browser.type("/")
      |> Browser.assert_has(".suggest")
      |> Browser.press(:escape)

      browser
      |> Browser.assert_input("/")
      |> Browser.refute_has(".suggest")
    else
      skip_browser()
    end
  end

  test "real browser textarea height is stable for single-line typing", %{browser: browser} do
    if browser do
      initial =
        Browser.evaluate(
          browser,
          "document.querySelector(\"textarea[name='input']\").getBoundingClientRect().height"
        )

      browser
      |> Browser.type("hello")

      final =
        Browser.evaluate(
          browser,
          "document.querySelector(\"textarea[name='input']\").getBoundingClientRect().height"
        )

      assert final == initial
    else
      skip_browser()
    end
  end

  defp skip_browser do
    IO.puts("Skipping browser driver smoke test: playwright executable is not available")
    assert true
  end
end
