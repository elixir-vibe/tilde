defmodule Tilde.Command.Builtin.Attach.Preview do
  @moduledoc false

  @type t :: %__MODULE__{
          first: String.t() | nil,
          last: String.t() | nil,
          row: String.t(),
          detail: String.t()
        }

  defstruct first: nil, last: nil, row: "", detail: ""

  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      first: Keyword.get(opts, :first),
      last: Keyword.get(opts, :last),
      row: Keyword.fetch!(opts, :row),
      detail: Keyword.fetch!(opts, :detail)
    }
  end
end
