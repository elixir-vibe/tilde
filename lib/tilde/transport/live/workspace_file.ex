defmodule Tilde.Transport.Live.WorkspaceFile do
  @moduledoc """
  LiveView component for the main read-only workspace file surface.
  """

  use Phoenix.Component

  import Tilde.Transport.Live.Footer

  alias Tilde.Core.{FileBuffer, FileSymbol}
  alias Tilde.Renderer.SyntaxHighlight

  attr(:file, FileBuffer, required: true)
  attr(:actions, :list, default: [])
  attr(:scroll_line, :integer, default: nil)

  def file_surface(assigns) do
    assigns = assign(assigns, :rendered, rendered(assigns.file))

    ~H"""
    <main
      id="tilde-workspace-file"
      class="buffer"
      aria-label="opened workspace file"
      data-scroll-line={@scroll_line}
      phx-hook="TildeWorkspaceFile"
    >
      <section :if={@file.error} class="error">
        {@file.error}
      </section>

      <section :if={!@file.error} class="body syntax">
        {Phoenix.HTML.raw(@rendered)}
      </section>

      <.footer left={file_status(@file)} actions={file_actions(@actions)} />
    </main>
    """
  end

  defp file_actions(actions) do
    actions ++ [%{event: "tilde:session:chat", label: "chat", shortcut: "tilde.session.chat"}]
  end

  defp file_status(%FileBuffer{} = file) do
    ["#{file.line_count} lines", "#{file.size} bytes", file.truncated? && "truncated"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp rendered(%FileBuffer{content: content, path: path, symbols: symbols}) do
    content
    |> SyntaxHighlight.to_html(path)
    |> mark_symbol_lines(symbols)
  rescue
    _exception in [ArgumentError, FunctionClauseError, RuntimeError] ->
      Phoenix.HTML.html_escape(content) |> Phoenix.HTML.safe_to_string()
  end

  defp mark_symbol_lines(html, []), do: html

  defp mark_symbol_lines(html, symbols) do
    symbols_by_line = Enum.group_by(symbols, & &1.line)

    Regex.replace(~r/<div class="l-line" data-line="(\d+)"/, html, fn match, line ->
      line = String.to_integer(line)

      case Map.get(symbols_by_line, line, []) do
        [] ->
          match

        symbols ->
          titles = Enum.map_join(symbols, " · ", &symbol_title/1)
          escaped = Phoenix.HTML.html_escape(titles) |> Phoenix.HTML.safe_to_string()

          ~s|<div class="l-line has-symbol" data-line="#{line}" data-symbol-title="#{escaped}"|
      end
    end)
  end

  defp symbol_title(%FileSymbol{} = symbol), do: "#{symbol.kind}: #{symbol.name}"
end
