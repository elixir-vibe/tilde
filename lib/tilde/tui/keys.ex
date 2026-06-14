defmodule Tilde.TUI.Keys do
  @moduledoc """
  Minimal key decoder for the SSH/TUI demo renderer.
  """

  @type key ::
          :toggle_expand
          | :quit
          | :redraw
          | :tab
          | :backtab
          | :enter
          | {:text, String.t()}
          | :unknown

  @doc "Decodes raw terminal bytes into a semantic key action."
  @spec decode(binary()) :: key()
  def decode(<<15>>), do: :toggle_expand
  def decode("q"), do: :quit
  def decode("r"), do: :redraw
  def decode("\t"), do: :tab
  def decode("\e[Z"), do: :backtab
  def decode("\r"), do: :enter
  def decode("\n"), do: :enter

  def decode(<<char::utf8>>) when char >= 32 do
    {:text, <<char::utf8>>}
  end

  def decode(_data), do: :unknown
end
