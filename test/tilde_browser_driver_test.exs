defmodule TildeBrowserDriverTest do
  use TildeTest.BrowserCase, async: false

  @moduletag :browser

  test "PlaywrightEx browser driver accepts slash suggestions with real JavaScript", %{
    browser: browser
  } do
    if browser do
      browser
      |> Browser.type("/")
      |> Browser.press(:down)
      |> Browser.press(:enter)

      assert Browser.evaluate(browser, "document.querySelector(\"textarea[name='input']\").value") =~
               "/"

      assert Browser.text(browser) =~ "commands"
    else
      skip_browser()
    end
  end

  test "real browser escape cancels slash suggestions without clearing input", %{browser: browser} do
    if browser do
      browser
      |> Browser.type("/")
      |> Browser.press(:escape)

      assert Browser.evaluate(browser, "document.querySelector(\"textarea[name='input']\").value") ==
               "/"

      Browser.wait_until(browser, "document.querySelector('.tilde-suggest') === null")
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
