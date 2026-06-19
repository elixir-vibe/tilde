defmodule Tilde.Demo.PlaygroundLiveTest do
  use TildeTest.BrowserCase, async: false

  @moduletag :browser

  test "browser renders semantic playground fixtures", %{browser: browser} do
    if browser do
      browser
      |> Browser.visit("/playground")
      |> Browser.assert_has("body .phx-connected")
      |> Browser.assert_text("Semantic component fixtures")
      |> Browser.assert_text("Tool success")
      |> Browser.assert_text("Tool error")
      |> Browser.assert_text("Streaming logs")
      |> Browser.assert_text("Long output")
      |> Browser.assert_text("Choice picker")
      |> Browser.assert_text("Thinking turn")
      |> Browser.assert_text("Search results")
      |> Browser.assert_text("web pi tool UI examples")
      |> Browser.assert_text("enter Confirm")
      |> Browser.assert_text("escape Cancel")
      |> Browser.assert_text("6 tests, 0 failures")
      |> Browser.assert_text("Apply the generated patch?")
      |> Browser.assert_text("Tilde keeps events and blocks semantic")

      refute Browser.text(browser) =~ "websearch query="
      refute Browser.text(browser) =~ "result row 12"

      assert Browser.evaluate(
               browser,
               "document.querySelector('#pg_long').dataset.expandKey === 'ctrl+o'"
             )

      assert Browser.evaluate(
               browser,
               "document.querySelector('#pg_choice .action.primary .shortcut .key').innerText === 'enter'"
             )

      assert Browser.evaluate(
               browser,
               """
               (() => getComputedStyle(document.querySelector('#pg_choice .actions')).justifyContent === 'flex-end')()
               """
             )

      assert Browser.evaluate(
               browser,
               "document.querySelector('.tool[data-block-id][data-expandable]').id === 'pg_long'"
             )

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 document.querySelector('#pg_search').scrollIntoView({block: 'center'})
                 document.dispatchEvent(new KeyboardEvent('keydown', {
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

      Browser.assert_positive_css_length(
        browser,
        "#pg_search .line.primary + .line.title",
        "margin-top"
      )

      browser
      |> Browser.click("#pg_long button")
      |> Browser.wait_until("document.body.innerText.includes('result row 12')")
      |> Browser.assert_text("result row 12")
    else
      skip_browser()
    end
  end

  defp skip_browser do
    IO.puts("Skipping playground browser smoke test: playwright executable is not available")
    assert true
  end
end
