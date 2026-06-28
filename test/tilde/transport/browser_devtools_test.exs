defmodule Tilde.Transport.BrowserDevtoolsTest do
  use TildeTest.BrowserCase

  @moduletag :browser

  test "single dev button toggles grid and exposes raw session as tooltip", %{browser: browser} do
    browser
    |> Browser.assert_has(".tilde .dev .button")
    |> Browser.click("button[phx-click='tilde:dev_toggle_grid']")
    |> Browser.assert_has(".tilde.grid")

    assert Browser.evaluate(
             browser,
             "document.querySelector('.dev .button').getAttribute('title') === null"
           )

    assert Browser.evaluate(browser, "document.querySelector('.dev .tooltip').textContent === ''")

    assert Browser.evaluate(
             browser,
             "document.querySelector('#tilde-dev-tooltip').dataset.raw.includes('%Tilde.Core.Session{')"
           )

    assert Browser.evaluate(
             browser,
             "document.querySelector('#tilde-dev-tooltip').dataset.raw.includes('agent_loop:')"
           )

    assert Browser.evaluate(
             browser,
             "document.querySelector('.footer .right .dev .button') !== null"
           )

    assert Browser.evaluate(
             browser,
             "['absolute', 'fixed'].includes(getComputedStyle(document.querySelector('#tilde-dev-tooltip')).position)"
           )

    assert Browser.evaluate(
             browser,
             """
             (async () => {
               const button = document.querySelector('#tilde-devtools .button')
               const tooltip = document.querySelector('#tilde-dev-tooltip')
               button.dispatchEvent(new PointerEvent('pointerenter', {bubbles: false}))
               await new Promise(resolve => setTimeout(resolve, 100))
               button.dispatchEvent(new PointerEvent('pointerleave', {bubbles: false}))
               tooltip.dispatchEvent(new PointerEvent('pointerenter', {bubbles: false}))
               await new Promise(resolve => setTimeout(resolve, 180))
               const rect = tooltip.getBoundingClientRect()
               const style = getComputedStyle(tooltip)

               return tooltip.dataset.open === 'true' &&
                 tooltip.textContent.includes('%Tilde.Core.Session{') &&
                 style.position === 'fixed' &&
                 style.visibility === 'visible' &&
                 style.pointerEvents === 'auto' &&
                 tooltip.scrollHeight > tooltip.clientHeight &&
                 rect.height > 100 &&
                 rect.width > 300
             })()
             """
           )
  end
end
