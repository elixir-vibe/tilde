defmodule Tilde.Core.Suggest do
  @moduledoc """
  Renderer-neutral autocomplete suggestions with stable selection.
  """

  defstruct id: "suggestions",
            title: "suggestions",
            trigger: "",
            query: "",
            items: [],
            selected_index: 0,
            selected_id: nil

  @type item :: %{label: String.t(), insert: String.t(), description: String.t()}
  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          trigger: String.t(),
          query: String.t(),
          items: [item()],
          selected_index: non_neg_integer(),
          selected_id: String.t() | nil
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
      selected_index: Keyword.get(opts, :selected_index, 0),
      selected_id: Keyword.get(opts, :selected_id)
    }
    |> clamp()
  end

  @doc "Returns the selected suggestion item."
  @spec selected(t()) :: item() | nil
  def selected(%__MODULE__{items: []}), do: nil
  def selected(%__MODULE__{} = suggest), do: Enum.at(suggest.items, suggest.selected_index)

  @doc "Returns the selected suggestion insert value."
  @spec accept(t()) :: String.t() | nil
  def accept(%__MODULE__{} = suggest) do
    case selected(suggest) do
      %{insert: insert} -> insert
      _other -> nil
    end
  end

  @doc "Moves selection to the next suggestion."
  @spec next(t()) :: t()
  def next(%__MODULE__{} = suggest), do: move(suggest, 1)

  @doc "Moves selection to the previous suggestion."
  @spec previous(t()) :: t()
  def previous(%__MODULE__{} = suggest), do: move(suggest, -1)

  @doc "Selects a suggestion by index."
  @spec select(t(), integer()) :: t()
  def select(%__MODULE__{} = suggest, index), do: clamp(%{suggest | selected_index: index})

  @doc "Selects a suggestion by stable item id."
  @spec select_id(t(), String.t() | nil) :: t()
  def select_id(%__MODULE__{} = suggest, id), do: clamp(%{suggest | selected_id: id})

  defp move(%__MODULE__{items: []} = suggest, _delta), do: suggest

  defp move(%__MODULE__{} = suggest, delta) do
    count = length(suggest.items)
    index = rem(suggest.selected_index + delta + count, count)
    %{suggest | selected_index: index, selected_id: item_id(Enum.at(suggest.items, index))}
  end

  defp clamp(%__MODULE__{items: []} = suggest),
    do: %{suggest | selected_index: 0, selected_id: nil}

  defp clamp(%__MODULE__{} = suggest) do
    index =
      selected_id_index(suggest) ||
        suggest.selected_index |> max(0) |> min(length(suggest.items) - 1)

    %{suggest | selected_index: index, selected_id: item_id(Enum.at(suggest.items, index))}
  end

  defp selected_id_index(%__MODULE__{selected_id: nil}), do: nil

  defp selected_id_index(%__MODULE__{} = suggest) do
    Enum.find_index(suggest.items, &(item_id(&1) == suggest.selected_id))
  end

  defp item_id(%{id: id}), do: to_string(id)
  defp item_id(%{insert: insert}), do: insert
  defp item_id(%{label: label}), do: label
  defp item_id(_item), do: nil
end
