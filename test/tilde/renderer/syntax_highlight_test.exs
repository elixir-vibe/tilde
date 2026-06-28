defmodule Tilde.Renderer.SyntaxHighlightTest do
  use TildeTest.Case, async: true

  alias Tilde.Renderer.SyntaxHighlight

  test "html formatter uses the shared Tilde syntax palette" do
    html = SyntaxHighlight.to_html("def hello, do: \"world\"\n", "lib/example.ex")

    assert html =~ "var(--syntax-keyword)"
    assert html =~ "var(--syntax-string)"
    assert html =~ "var(--syntax-function)"
  end
end
