defmodule Tilde.Core.Palette.Item do
  @moduledoc """
  Renderer-neutral command palette item.
  """

  defstruct id: "", label: "", detail: nil, kind: :file, action: %{}

  @type kind :: :file | :command | :symbol

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          detail: String.t() | nil,
          kind: kind(),
          action: map()
        }

  @doc "Builds a palette item."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      id: Keyword.fetch!(opts, :id),
      label: Keyword.fetch!(opts, :label),
      detail: Keyword.get(opts, :detail),
      kind: Keyword.get(opts, :kind, :file),
      action: Keyword.get(opts, :action, %{})
    }
  end
end
