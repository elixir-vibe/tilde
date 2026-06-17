defmodule Tilde.Tool.View.Stream do
  @moduledoc "Renderer-neutral semantic tool stream view."

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          lines: [String.t()],
          hidden_lines: non_neg_integer(),
          byte_count: non_neg_integer(),
          line_count: non_neg_integer()
        }

  defstruct id: nil, kind: :stdout, lines: [], hidden_lines: 0, byte_count: 0, line_count: 0
end
