defmodule Tilde.Action do
  @moduledoc """
  Semantic action available on a block or widget.

  Renderers may expose actions as keyboard shortcuts, buttons, menu items, or
  accessibility controls.
  """

  @type kind :: :normal | :primary | :danger

  @type t :: %__MODULE__{
          id: atom() | String.t(),
          label: String.t(),
          kind: kind(),
          key: String.t() | nil,
          metadata: map()
        }

  defstruct id: nil, label: "", kind: :normal, key: nil, metadata: %{}

  @doc "Creates an action."
  @spec new(atom() | String.t(), String.t(), keyword()) :: t()
  def new(id, label, opts \\ []) do
    %__MODULE__{
      id: id,
      label: label,
      kind: Keyword.get(opts, :kind, :normal),
      key: Keyword.get(opts, :key),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
