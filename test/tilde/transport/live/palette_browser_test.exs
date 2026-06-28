defmodule Tilde.Transport.Live.PaletteBrowserTest do
  use TildeTest.BrowserCase, async: false

  @moduletag :browser

  test "opening the palette overlays without shifting the workbench layout", %{browser: browser} do
    if browser do
      before = workbench_boxes(browser)

      browser
      |> Browser.press(:ctrl_p)
      |> Browser.wait_until("document.querySelector('#tilde-palette') !== null")

      after_open = workbench_boxes(browser)

      assert before["workspace"] == after_open["workspace"]
      assert before["main"] == after_open["main"]

      assert Browser.evaluate(
               browser,
               "getComputedStyle(document.querySelector('.palette-layer')).position === 'fixed'"
             )

      assert Browser.evaluate(
               browser,
               "document.querySelector('#tilde-palette .choices').scrollHeight > document.querySelector('#tilde-palette .choices').clientHeight"
             )
    else
      skip_browser()
    end
  end

  defp workbench_boxes(browser) do
    Browser.evaluate(
      browser,
      """
      (() => {
        const box = selector => {
          const rect = document.querySelector(selector).getBoundingClientRect()

          return {
            left: Math.round(rect.left),
            top: Math.round(rect.top),
            width: Math.round(rect.width),
            height: Math.round(rect.height)
          }
        }

        return {
          workspace: box('.workspace'),
          main: box('.main')
        }
      })()
      """
    )
  end

  defp skip_browser do
    IO.puts("Skipping palette browser test: playwright executable is not available")
    assert true
  end
end
