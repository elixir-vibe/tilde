defmodule Tilde.Transport.Live.ReviewBrowserTest do
  use TildeTest.BrowserCase, async: false

  @moduletag :browser

  test "right review pane stays visible and opens files from comments", %{browser: browser} do
    if browser do
      browser
      |> Browser.assert_has(".workspace")
      |> Browser.assert_has(".review")
      |> Browser.assert_has(".main")

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 const file = document.querySelector('.review .file .path')
                 if (!file) return false
                 file.click()
                 return true
               })()
               """
             )

      browser
      |> Browser.wait_until("document.querySelector('#tilde-workspace-file') !== null")

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 return !!document.querySelector('.workspace') &&
                   !!document.querySelector('.review') &&
                   !!document.querySelector('#tilde-workspace-file') &&
                   !!document.querySelector('.review .comment.selected') &&
                   Array.from(document.querySelectorAll('.footer .action')).some((action) =>
                     action.getAttribute('phx-click') === 'tilde:review:focus' &&
                       action.textContent.includes('r') &&
                       action.textContent.includes('review')
                   ) &&
                   Array.from(document.querySelectorAll('.workspace .views .action.selected')).some((action) =>
                     action.textContent.includes('f') && action.textContent.includes('files')
                   )
               })()
               """
             )

      browser
      |> Browser.press("body", :r)
      |> Browser.wait_until("document.querySelector('#tilde-workspace-file') !== null")

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 return !!document.querySelector('.review .comment.selected') &&
                   Array.from(document.querySelectorAll('.workspace .views .action.selected')).some((action) =>
                     action.textContent.includes('f') && action.textContent.includes('files')
                   )
               })()
               """
             )

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 const resolve = document.querySelector('.review .comment.selected .action')
                 if (!resolve || resolve.innerText.trim() !== 'resolve') return false
                 resolve.click()
                 return true
               })()
               """
             )

      browser
      |> Browser.wait_until(
        "document.querySelector('.review .comment.selected.resolved') !== null"
      )

      assert Browser.evaluate(
               browser,
               """
               (() => {
                 const reopen = document.querySelector('.review .comment.selected .action')
                 if (!reopen || reopen.innerText.trim() !== 'reopen') return false
                 reopen.click()
                 return true
               })()
               """
             )

      browser
      |> Browser.wait_until("document.querySelector('.review .comment.selected.open') !== null")
    else
      skip_browser()
    end
  end

  defp skip_browser do
    IO.puts("Skipping review browser test: playwright executable is not available")
    assert true
  end
end
