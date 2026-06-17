defmodule Tilde.Core.Widget do
  @moduledoc """
  Semantic widget mounted outside the historical transcript.

  Widgets model pi-like regions such as content above the input editor, below the
  editor, footer/statusline content, overlays, and sidecars. They are ephemeral
  UI state, not transcript history, unless an application also emits events for
  them.
  """

  alias Tilde.Core.Action

  @type placement :: :above_input | :below_input | :footer | :overlay | :sidecar

  @type t :: %__MODULE__{
          id: String.t(),
          placement: placement(),
          kind: atom(),
          content: term(),
          actions: [Action.t()],
          metadata: map()
        }

  defstruct id: nil,
            placement: :above_input,
            kind: :content,
            content: nil,
            actions: [],
            metadata: %{}

  @doc "Creates a widget."
  @spec new(String.t(), placement(), term(), keyword()) :: t()
  def new(id, placement, content, opts \\ []) when is_binary(id) do
    %__MODULE__{
      id: id,
      placement: placement,
      kind: Keyword.get(opts, :kind, :content),
      content: content,
      actions: Keyword.get(opts, :actions, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
