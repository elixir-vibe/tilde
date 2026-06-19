defmodule Tilde.Transport.Live.ConsoleShortcutTest do
  use TildeTest.BrowserCase, async: false

  @moduletag :browser

  test "global expand shortcut is captured before focused descendants stop propagation", %{
    browser: browser
  } do
    if browser do
      browser
      |> Browser.visit("/playground")
      |> Browser.assert_has("body .phx-connected")

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 const tool = document.querySelector('#pg_search')
                 tool.scrollIntoView({block: 'center'})
                 tool.addEventListener('keydown', event => event.stopPropagation(), {once: true})
                 tool.dispatchEvent(new KeyboardEvent('keydown', {
                   key: 'o',
                   ctrlKey: true,
                   bubbles: true,
                   cancelable: true
                 }))
                 return true
               })()
               """
             )

      browser
      |> Browser.wait_until("document.body.innerText.includes('branch isolation')")
      |> Browser.assert_text("branch isolation")
    else
      skip_browser()
    end
  end

  defp skip_browser do
    IO.puts("Skipping console shortcut browser test: playwright executable is not available")
    assert true
  end
end
