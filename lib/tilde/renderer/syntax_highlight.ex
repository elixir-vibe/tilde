defmodule Tilde.Renderer.SyntaxHighlight do
  @moduledoc "Renderer syntax highlighting boundary backed by Lumis."

  alias Lumis.Theme

  @tilde_theme %Theme{
    name: "tilde",
    appearance: :light,
    revision: "tilde-css-vars",
    highlights: %{
      "normal" => %Theme.Style{fg: "var(--color-fg)", bg: "transparent"},
      "comment" => %Theme.Style{fg: "var(--color-muted)"},
      "comment.documentation" => %Theme.Style{fg: "var(--color-muted)"},
      "constant" => %Theme.Style{fg: "var(--color-warning)"},
      "constant.builtin" => %Theme.Style{fg: "var(--color-warning)"},
      "constructor" => %Theme.Style{fg: "var(--color-fg)"},
      "function" => %Theme.Style{fg: "var(--color-fg)"},
      "function.call" => %Theme.Style{fg: "var(--color-fg)"},
      "function.macro" => %Theme.Style{fg: "var(--color-fg)"},
      "keyword" => %Theme.Style{fg: "var(--color-link)", bold: true},
      "keyword.function" => %Theme.Style{fg: "var(--color-link)", bold: true},
      "module" => %Theme.Style{fg: "var(--color-link)"},
      "number" => %Theme.Style{fg: "var(--color-fg)"},
      "operator" => %Theme.Style{fg: "var(--color-muted)"},
      "property" => %Theme.Style{fg: "var(--color-fg)"},
      "punctuation.bracket" => %Theme.Style{fg: "var(--color-muted)"},
      "punctuation.delimiter" => %Theme.Style{fg: "var(--color-muted)"},
      "string" => %Theme.Style{fg: "var(--color-fg)"},
      "string.special" => %Theme.Style{fg: "var(--color-warning)"},
      "string.special.symbol" => %Theme.Style{fg: "var(--color-warning)"},
      "tag" => %Theme.Style{fg: "var(--color-link)"},
      "type" => %Theme.Style{fg: "var(--color-link)"},
      "variable" => %Theme.Style{fg: "var(--color-fg)"},
      "variable.builtin" => %Theme.Style{fg: "var(--color-fg)"}
    }
  }

  @spec to_html(String.t(), String.t()) :: String.t()
  def to_html(source, path) when is_binary(source) and is_binary(path) do
    Lumis.highlight!(source, formatter: {:html_inline, language: path, theme: @tilde_theme})
  end

  @spec to_terminal(String.t(), String.t()) :: String.t()
  def to_terminal(source, path) when is_binary(source) and is_binary(path) do
    Lumis.highlight!(source, formatter: {:terminal, language: path})
  end
end
