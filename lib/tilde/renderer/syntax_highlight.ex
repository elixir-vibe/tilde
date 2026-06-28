defmodule Tilde.Renderer.SyntaxHighlight do
  @moduledoc "Renderer syntax highlighting boundary backed by Lumis."

  alias Lumis.Theme

  @tilde_theme %Theme{
    name: "tilde",
    appearance: :light,
    revision: "tilde-css-vars",
    highlights: %{
      "normal" => %Theme.Style{fg: "var(--color-fg)", bg: "transparent"},
      "comment" => %Theme.Style{fg: "var(--syntax-comment)", italic: true},
      "comment.documentation" => %Theme.Style{fg: "var(--syntax-comment)", italic: true},
      "constant" => %Theme.Style{fg: "var(--syntax-constant)"},
      "constant.builtin" => %Theme.Style{fg: "var(--syntax-constant)", bold: true},
      "constructor" => %Theme.Style{fg: "var(--syntax-module)"},
      "function" => %Theme.Style{fg: "var(--syntax-function)"},
      "function.call" => %Theme.Style{fg: "var(--syntax-function)"},
      "function.macro" => %Theme.Style{fg: "var(--syntax-attribute)"},
      "keyword" => %Theme.Style{fg: "var(--syntax-keyword)", bold: true},
      "keyword.function" => %Theme.Style{fg: "var(--syntax-keyword)", bold: true},
      "module" => %Theme.Style{fg: "var(--syntax-module)", bold: true},
      "number" => %Theme.Style{fg: "var(--syntax-constant)"},
      "operator" => %Theme.Style{fg: "var(--syntax-punctuation)"},
      "property" => %Theme.Style{fg: "var(--syntax-attribute)"},
      "punctuation.bracket" => %Theme.Style{fg: "var(--syntax-punctuation)"},
      "punctuation.delimiter" => %Theme.Style{fg: "var(--syntax-punctuation)"},
      "string" => %Theme.Style{fg: "var(--syntax-string)"},
      "string.special" => %Theme.Style{fg: "var(--syntax-constant)"},
      "string.special.symbol" => %Theme.Style{fg: "var(--syntax-constant)"},
      "tag" => %Theme.Style{fg: "var(--syntax-keyword)"},
      "type" => %Theme.Style{fg: "var(--syntax-module)"},
      "variable" => %Theme.Style{fg: "var(--color-fg)"},
      "variable.builtin" => %Theme.Style{fg: "var(--syntax-constant)"}
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
