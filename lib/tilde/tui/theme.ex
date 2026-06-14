defmodule Tilde.TUI.Theme do
  @moduledoc """
  ANSI styling helpers for Tilde's terminal renderers.

  ANSI is renderer output only. Semantic Tilde structs never store ANSI escapes.
  """

  @type style ::
          :title
          | :muted
          | :accent
          | :success
          | :error
          | :warning
          | :underline
          | :tool_pending_bg
          | :tool_success_bg
          | :tool_error_bg
          | :cell_bg

  @doc "Styles text with `IO.ANSI` helpers."
  @spec style(String.t(), style() | [style()], keyword()) :: String.t()
  def style(text, styles, opts \\ []) when is_binary(text) do
    if Keyword.get(opts, :ansi, true) do
      styles
      |> List.wrap()
      |> Enum.flat_map(&ansi/1)
      |> Kernel.++([text, :reset])
      |> IO.ANSI.format_fragment(true)
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
  def tool_pending(text, opts \\ []), do: style(text, :tool_pending_bg, opts)
  def tool_success(text, opts \\ []), do: style(text, :tool_success_bg, opts)
  def tool_error(text, opts \\ []), do: style(text, :tool_error_bg, opts)
  def cell(text, opts \\ []), do: style(text, :cell_bg, opts)

  defp ansi(:title), do: [:bright]
  defp ansi(:muted), do: [:faint]
  defp ansi(:accent), do: [:magenta]
  defp ansi(:success), do: [:green]
  defp ansi(:error), do: [:red]
  defp ansi(:warning), do: [:yellow]
  defp ansi(:underline), do: [:underline]
  defp ansi(:tool_pending_bg), do: [:yellow_background, :black]
  defp ansi(:tool_success_bg), do: [:green_background, :black]
  defp ansi(:tool_error_bg), do: [:red_background, :white]
  defp ansi(:cell_bg), do: [:light_black_background]
end
