defmodule Tilde.Tool.View.Call do
  @moduledoc "Renderer-neutral semantic tool call view."

  alias Tilde.Tool.View.Segment

  @type t :: %__MODULE__{
          title: String.t(),
          segments: [Segment.t()],
          tags: [String.t()],
          suffix: String.t() | nil
        }

  defstruct title: "", segments: [], tags: [], suffix: nil

  @spec new(String.t(), keyword()) :: t()
  def new(title, opts \\ []) do
    %__MODULE__{
      title: title,
      segments: Enum.map(Keyword.get(opts, :segments, []), &segment/1),
      tags: Keyword.get(opts, :tags, []),
      suffix: Keyword.get(opts, :suffix)
    }
  end

  defp segment(%Segment{} = segment), do: segment
  defp segment(%{text: text} = map), do: Segment.new(text, color: Map.get(map, :color))
  defp segment(text), do: Segment.new(text)
end
