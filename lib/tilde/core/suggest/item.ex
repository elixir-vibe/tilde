defmodule Tilde.Core.Suggest.Item do
  @moduledoc "Strict suggestion item data shared by renderers."

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          insert: String.t(),
          description: String.t(),
          detail: String.t() | nil,
          metadata: map()
        }

  defstruct id: "", label: "", insert: "", description: "", detail: nil, metadata: %{}

  @spec new(keyword()) :: t()
  def new(opts) do
    label = Keyword.fetch!(opts, :label)
    insert = Keyword.fetch!(opts, :insert)

    %__MODULE__{
      id: Keyword.get(opts, :id, insert),
      label: label,
      insert: insert,
      description: Keyword.get(opts, :description, ""),
      detail: Keyword.get(opts, :detail),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
