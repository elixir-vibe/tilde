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
  end
end
