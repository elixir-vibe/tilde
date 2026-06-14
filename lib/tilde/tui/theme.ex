defmodule Tilde.TUI.Theme do
  @moduledoc """
  ANSI styling helpers for Tilde's terminal renderers.

  ANSI is renderer output only. Semantic Tilde structs never store ANSI escapes.
  """

  @type style :: :title | :muted | :accent | :success | :error | :warning | :underline

  @doc "Styles text with `IO.ANSI` helpers."
  @spec style(String.t(), style() | [style()], keyword()) :: String.t()
  def style(text, styles, opts \\ []) when is_binary(text) do
    if Keyword.get(opts, :ansi, true) do
      styles
      |> List.wrap()
      |> Enum.flat_map(&ansi/1)
      |> Kernel.++([text, :reset])
      |> IO.ANSI.format_fragment()
      |> IO.iodata_to_binary()
    else
      text
    end
  end

  def title(text, opts \\ []), do: style(text, :title, opts)
  def muted(text, opts \\ []), do: style(text, :muted, opts)
  def accent(text, opts \\ []), do: style(text, :accent, opts)
  def success(text, opts \\ []), do: style(text, :success, opts)
  def error(text, opts \\ []), do: style(text, :error, opts)
  def warning(text, opts \\ []), do: style(text, :warning, opts)
  def underline(text, opts \\ []), do: style(text, :underline, opts)

  defp ansi(:title), do: [:bright]
  defp ansi(:muted), do: [:faint]
  defp ansi(:accent), do: [:magenta]
  defp ansi(:success), do: [:green]
  defp ansi(:error), do: [:red]
  defp ansi(:warning), do: [:yellow]
  defp ansi(:underline), do: [:underline]
end
