defmodule Tilde.Core.FileSymbol do
  @moduledoc """
  Renderer-neutral source symbol found in an opened file buffer.
  """

  defstruct name: "",
            kind: :function,
            line: 1,
            column: 1,
            end_line: 1,
            end_column: 1,
            detail: ""

  @type kind ::
          :module | :function | :macro | :delegate | :struct | :type | :callback | :attribute

  @type t :: %__MODULE__{
          name: String.t(),
          kind: kind(),
          line: pos_integer(),
          column: pos_integer(),
          end_line: pos_integer(),
          end_column: pos_integer(),
          detail: String.t()
        }

  @doc "Builds a file symbol."
  @spec new(keyword()) :: t()
  def new(opts) do
    line = Keyword.get(opts, :line, 1)
    column = Keyword.get(opts, :column, 1)

    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      kind: Keyword.get(opts, :kind, :function),
      line: line,
      column: column,
      end_line: Keyword.get(opts, :end_line, line),
      end_column: Keyword.get(opts, :end_column, column),
      detail: Keyword.get(opts, :detail, "")
    }
  end
end
