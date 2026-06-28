defmodule Tilde.Runtime.CodeIntelligenceTest do
  use TildeTest.Case, async: true

  alias Tilde.Runtime.CodeIntelligence

  test "extracts Elixir document symbols with Sourceror" do
    symbols =
      CodeIntelligence.document_symbols(
        """
        defmodule Example do
          def public(value), do: value
          defp private, do: :ok
          defmacro macro(value), do: value
        end
        """,
        "lib/example.ex"
      )

    assert Enum.map(symbols, & &1.name) == [
             "Example",
             "def public/1",
             "defp private/0",
             "defmacro macro/1"
           ]

    assert Enum.map(symbols, & &1.kind) == [:module, :function, :function, :macro]
    assert Enum.map(symbols, & &1.line) == [1, 2, 3, 4]
  end

  test "extracts struct, type, and callback symbols" do
    symbols =
      CodeIntelligence.document_symbols(
        """
        defmodule Example.Schema do
          defstruct [:id]

          @type t :: %__MODULE__{id: integer()}
          @typep id :: integer()
          @opaque token :: binary()

          @callback run(term()) :: term()
          @macrocallback build(term()) :: Macro.t()
        end
        """,
        "lib/example/schema.ex"
      )

    assert Enum.map(symbols, & &1.name) == [
             "Example.Schema",
             "defstruct",
             "@type t/0",
             "@typep id/0",
             "@opaque token/0",
             "@callback run/1",
             "@macrocallback build/1"
           ]

    assert Enum.map(symbols, & &1.kind) == [
             :module,
             :struct,
             :type,
             :type,
             :type,
             :callback,
             :callback
           ]

    assert Enum.map(symbols, & &1.detail) == [
             "module",
             "defstruct",
             "@type",
             "@typep",
             "@opaque",
             "@callback",
             "@macrocallback"
           ]

    assert Enum.map(symbols, & &1.line) == [1, 2, 4, 5, 6, 8, 9]
  end

  test "ignores non-Elixir files and invalid source" do
    assert CodeIntelligence.document_symbols("body {}", "assets/app.css") == []
    assert CodeIntelligence.document_symbols("defmodule Broken do", "lib/broken.ex") == []
  end
end
