defmodule TildeTest.BrowserCase do
  @moduledoc "Case template for PlaywrightEx browser integration tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      alias TildeTest.Driver.Browser

      setup do
        if Browser.available?() do
          state = Browser.open()
          on_exit(fn -> Browser.close(state) end)
          {:ok, browser: state}
        else
          ExUnit.configure(exclude: [:browser])
          {:ok, browser: nil}
        end
      end
    end
  end
end
