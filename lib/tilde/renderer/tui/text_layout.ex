defmodule Tilde.Renderer.TUI.TextLayout do
  @moduledoc "Shared terminal text measurement and clipping helpers."

  @spec pad(String.t(), non_neg_integer()) :: String.t()
  def pad(text, width), do: text <> String.duplicate(" ", max(width - visible_width(text), 0))

  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(text, width) do
    if visible_width(text) <= width do
      text
    else
      text |> String.graphemes() |> Enum.take(max(width - 1, 0)) |> Enum.join() |> Kernel.<>("…")
    end
  end

  @spec visible_width(String.t()) :: non_neg_integer()
  def visible_width(text), do: text |> strip_ansi() |> String.length()

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
end
