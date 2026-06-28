defmodule Tilde.Core.FileBuffer do
  @moduledoc """
  Renderer-neutral read-only file content opened in the main workspace surface.

  The workspace pane can point at files, but the opened content is a separate
  top-level concept: a bounded file buffer shown instead of the chat surface.
  """

  alias Tilde.Core.FileSymbol

  defstruct path: "",
            content: "",
            size: 0,
            line_count: 0,
            truncated?: false,
            error: nil,
            symbols: []

  @type t :: %__MODULE__{
          path: String.t(),
          content: String.t(),
          size: non_neg_integer(),
          line_count: non_neg_integer(),
          truncated?: boolean(),
          error: String.t() | nil,
          symbols: [FileSymbol.t()]
        }

  @doc "Builds a file buffer value."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    content = Keyword.get(opts, :content, "")

    %__MODULE__{
      path: Keyword.get(opts, :path, ""),
      content: content,
      size: Keyword.get(opts, :size, byte_size(content)),
      line_count: Keyword.get(opts, :line_count, line_count(content)),
      truncated?: Keyword.get(opts, :truncated?, false),
      error: Keyword.get(opts, :error),
      symbols: Keyword.get(opts, :symbols, [])
    }
  end

  defp line_count(""), do: 0
  defp line_count(content), do: content |> String.split("\n") |> length()
end
