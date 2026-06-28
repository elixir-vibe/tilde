defmodule Tilde.Renderer.TUI.WorkspaceFile do
  @moduledoc "Terminal renderer for the read-only workspace file buffer."

  alias Tilde.Core.FileBuffer
  alias Tilde.Renderer.SyntaxHighlight
  alias Tilde.Renderer.TUI.Theme

  @doc "Renders a file buffer with compact line numbers."
  @spec render(FileBuffer.t() | nil, pos_integer(), keyword()) :: String.t()
  def render(file, width, opts \\ [])

  def render(nil, _width, opts), do: Theme.muted("No file open.", opts)

  def render(%FileBuffer{error: error} = file, _width, opts) when is_binary(error) do
    [Theme.title(file.path, opts), Theme.error(error, opts)]
    |> Enum.join("\n")
  end

  def render(%FileBuffer{} = file, width, opts) do
    body_width = max(width - 8, 20)

    body =
      file.content
      |> highlighted(file.path, opts)
      |> String.split("\n")
      |> Enum.with_index(1)
      |> visible_lines(opts)
      |> Enum.map_join("\n", fn {line, number} -> line(number, line, body_width, opts) end)

    status =
      ["#{file.line_count} lines", "#{file.size} bytes", file.truncated? && "truncated"]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" · ")

    [Theme.title(file.path, opts), body, Theme.muted(status, opts)]
    |> Enum.join("\n")
  end

  defp highlighted(source, path, opts) do
    if Keyword.get(opts, :ansi, true) do
      SyntaxHighlight.to_terminal(source, path)
    else
      source
    end
  rescue
    _exception in [ArgumentError, FunctionClauseError, RuntimeError] -> source
  end

  defp visible_lines(lines, opts) do
    viewport_height = Keyword.get(opts, :viewport_height)
    active_line = Keyword.get(opts, :active_line)
    scroll_line = Keyword.get(opts, :scroll_line)

    cond do
      is_integer(scroll_line) and scroll_line > 0 and is_integer(viewport_height) ->
        window(lines, scroll_line, viewport_height)

      is_integer(active_line) and active_line > 0 ->
        radius = Keyword.get(opts, :line_context, 8)
        height = viewport_height || radius * 2 + 1
        start_line = max(active_line - div(height, 2), 1)

        window(lines, start_line, height)

      is_integer(viewport_height) ->
        window(lines, 1, viewport_height)

      true ->
        lines
    end
  end

  defp window(lines, start_line, height) do
    end_line = start_line + max(height, 1) - 1

    Enum.filter(lines, fn {_source, number} -> number >= start_line and number <= end_line end)
  end

  defp line(number, source, width, opts) do
    active? = number == Keyword.get(opts, :active_line)
    marker = if active?, do: Theme.accent("›", opts), else: " "
    gutter = number |> Integer.to_string() |> String.pad_leading(4)
    Theme.muted(marker <> gutter <> " │ ", opts) <> truncate(source, width)
  end

  defp truncate(line, width) do
    plain = strip_ansi(line)

    if String.length(plain) <= width do
      line
    else
      String.slice(plain, 0, max(width - 1, 0)) <> "…"
    end
  end

  defp strip_ansi(text), do: Regex.replace(~r/\e\[[0-9;]*[A-Za-z]/, text, "")
end
