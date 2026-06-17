defmodule Tilde.Tool.View.Result do
  @moduledoc "Renderer-neutral semantic tool result view."

  alias Tilde.Tool.View.Stream

  @type t :: %__MODULE__{
          metadata_rows: [{atom(), String.t()}],
          lines: [String.t()],
          streams: [Stream.t()],
          hidden_lines: non_neg_integer(),
          waiting?: boolean()
        }

  defstruct metadata_rows: [], lines: [], streams: [], hidden_lines: 0, waiting?: false

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      metadata_rows: Keyword.get(opts, :metadata_rows, []),
      lines: Keyword.get(opts, :lines, []),
      streams: Keyword.get(opts, :streams, []),
      hidden_lines: Keyword.get(opts, :hidden_lines, 0),
      waiting?: Keyword.get(opts, :waiting?, false)
    }
  end
end
