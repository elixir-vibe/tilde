defmodule Tilde.Core.Display do
  @moduledoc """
  Renderer-neutral display preferences for a block.

  Display state is not content. Toggling expansion changes this struct, not the
  stored message text or tool stream chunks.
  """

  @type compact_limit :: {:lines, pos_integer()} | {:bytes, pos_integer()}

  @type t :: %__MODULE__{
          expanded?: boolean(),
          compact_limit: compact_limit(),
          expand_key: String.t()
        }

  defstruct expanded?: false, compact_limit: {:lines, 8}, expand_key: "ctrl+o"

  @doc "Toggles expanded mode."
  @spec toggle(t()) :: t()
  def toggle(%__MODULE__{} = display), do: %{display | expanded?: !display.expanded?}

  @doc "Applies a map of display updates."
  @spec merge(t(), map()) :: t()
  def merge(%__MODULE__{} = display, attrs) when is_map(attrs) do
    struct!(display, attrs)
  end
end
