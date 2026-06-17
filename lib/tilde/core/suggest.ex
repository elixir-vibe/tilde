defmodule Tilde.Core.Suggest do
  @moduledoc """
  Renderer-neutral autocomplete suggestions.
  """

  defstruct id: "suggestions",
            title: "suggestions",
            trigger: "",
            query: "",
            items: [],
            selected_index: 0

  @type item :: %{label: String.t(), insert: String.t(), description: String.t()}
  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          trigger: String.t(),
          query: String.t(),
          items: [item()],
          selected_index: non_neg_integer()
        }

  @doc "Creates a suggestion set."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, "suggestions"),
      title: Keyword.get(opts, :title, "suggestions"),
      trigger: Keyword.get(opts, :trigger, ""),
      query: Keyword.get(opts, :query, ""),
      items: Keyword.get(opts, :items, []),
      selected_index: Keyword.get(opts, :selected_index, 0)
    }
    |> clamp()
  end

  @doc "Returns the selected suggestion item."
  @spec selected(t()) :: item() | nil
  def selected(%__MODULE__{items: []}), do: nil
  def selected(%__MODULE__{} = suggest), do: Enum.at(suggest.items, suggest.selected_index)

  @doc "Moves selection to the next suggestion."
  @spec next(t()) :: t()
  def next(%__MODULE__{} = suggest), do: move(suggest, 1)

  @doc "Moves selection to the previous suggestion."
  @spec previous(t()) :: t()
  def previous(%__MODULE__{} = suggest), do: move(suggest, -1)

  @doc "Selects a suggestion by index."
  @spec select(t(), integer()) :: t()
  def select(%__MODULE__{} = suggest, index), do: clamp(%{suggest | selected_index: index})

  defp move(%__MODULE__{items: []} = suggest, _delta), do: suggest

  defp move(%__MODULE__{} = suggest, delta) do
    count = length(suggest.items)
    index = rem(suggest.selected_index + delta + count, count)
    %{suggest | selected_index: index}
  end

  defp clamp(%__MODULE__{items: []} = suggest), do: %{suggest | selected_index: 0}

  defp clamp(%__MODULE__{} = suggest) do
    index = suggest.selected_index |> max(0) |> min(length(suggest.items) - 1)
    %{suggest | selected_index: index}
  end
end
