defmodule Tilde.Core.Keys do
  @moduledoc """
  Minimal key decoder for the SSH/TUI demo renderer.
  """

  @type key ::
          :toggle_expand
          | :quit
          | :redraw
          | :palette_open
          | :tab
          | :backtab
          | :up
          | :down
          | :page_up
          | :page_down
          | :suggest_next
          | :suggest_previous
          | :suggest_accept
          | :enter
          | :backspace
          | :cancel
          | :interrupt
          | {:text, String.t()}
          | :unknown

  @doc "Decodes raw terminal bytes into one or more semantic key actions."
  @spec decode_many(binary()) :: [key()]
  def decode_many("q"), do: [:quit]
  def decode_many("q\r"), do: [:quit]
  def decode_many("q\n"), do: [:quit]
  def decode_many("r"), do: [:redraw]
  def decode_many("r\r"), do: [:redraw]
  def decode_many("r\n"), do: [:redraw]
  def decode_many(data) when is_binary(data), do: do_decode_many(data, [])

  @doc "Decodes raw terminal bytes into a semantic key action."
  @spec decode(binary()) :: key()
  def decode(<<16>>), do: :palette_open
  def decode(<<15>>), do: :toggle_expand
  def decode("q"), do: :quit
  def decode("r"), do: :redraw
  def decode("\t"), do: :tab
  def decode("\e[Z"), do: :backtab
  def decode("\e[A"), do: :up
  def decode("\e[B"), do: :down
  def decode("\e[5~"), do: :page_up
  def decode("\e[6~"), do: :page_down
  def decode("\r"), do: :enter
  def decode("\n"), do: :enter
  def decode(<<3>>), do: :interrupt
  def decode(<<27>>), do: :cancel
  def decode(<<8>>), do: :backspace
  def decode(<<127>>), do: :backspace

  def decode(<<char::utf8>>) when char >= 32 do
    {:text, <<char::utf8>>}
  end

  def decode(_data), do: :unknown

  defp do_decode_many("", keys), do: Enum.reverse(keys)

  defp do_decode_many(<<16, rest::binary>>, keys),
    do: do_decode_many(rest, [:palette_open | keys])

  defp do_decode_many(<<15, rest::binary>>, keys),
    do: do_decode_many(rest, [:toggle_expand | keys])

  defp do_decode_many(<<3, rest::binary>>, keys), do: do_decode_many(rest, [:interrupt | keys])

  defp do_decode_many(<<27, ?[, ?Z, rest::binary>>, keys),
    do: do_decode_many(rest, [:backtab | keys])

  defp do_decode_many(<<27, ?[, ?A, rest::binary>>, keys),
    do: do_decode_many(rest, [:up | keys])

  defp do_decode_many(<<27, ?[, ?B, rest::binary>>, keys),
    do: do_decode_many(rest, [:down | keys])

  defp do_decode_many(<<27, ?[, ?5, ?~, rest::binary>>, keys),
    do: do_decode_many(rest, [:page_up | keys])

  defp do_decode_many(<<27, ?[, ?6, ?~, rest::binary>>, keys),
    do: do_decode_many(rest, [:page_down | keys])

  defp do_decode_many(<<27, rest::binary>>, keys), do: do_decode_many(rest, [:cancel | keys])
  defp do_decode_many(<<9, rest::binary>>, keys), do: do_decode_many(rest, [:tab | keys])
  defp do_decode_many(<<8, rest::binary>>, keys), do: do_decode_many(rest, [:backspace | keys])
  defp do_decode_many(<<127, rest::binary>>, keys), do: do_decode_many(rest, [:backspace | keys])
  defp do_decode_many(<<13, rest::binary>>, keys), do: do_decode_many(rest, [:enter | keys])
  defp do_decode_many(<<10, rest::binary>>, keys), do: do_decode_many(rest, [:enter | keys])

  defp do_decode_many(<<char::utf8, rest::binary>>, keys) when char >= 32 do
    do_decode_many(rest, [{:text, <<char::utf8>>} | keys])
  end

  defp do_decode_many(<<_byte, rest::binary>>, keys), do: do_decode_many(rest, [:unknown | keys])
end
