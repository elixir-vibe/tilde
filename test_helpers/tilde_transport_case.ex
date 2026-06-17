defmodule TildeTest.TransportCase do
  @moduledoc "Case template for shared Live/TUI transport behavior tests."

  use ExUnit.CaseTemplate

  using do
    quote do
      import TildeTest.TransportCase
      alias TildeTest.Driver
    end
  end

  @doc "Declares the default fast behavior drivers."
  def fast_drivers, do: [TildeTest.Driver.Live, TildeTest.Driver.TUI]
end
