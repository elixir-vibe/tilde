defmodule Tilde.Suggest do
  @moduledoc """
  Renderer-neutral autocomplete suggestions.
  """

  defstruct id: "suggestions", title: "suggestions", trigger: "", query: "", items: []

  @type item :: %{label: String.t(), insert: String.t(), description: String.t()}
  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t(),
          trigger: String.t(),
          query: String.t(),
          items: [item()]
        }

  @doc "Creates a suggestion set."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, "suggestions"),
      title: Keyword.get(opts, :title, "suggestions"),
      trigger: Keyword.get(opts, :trigger, ""),
      query: Keyword.get(opts, :query, ""),
      items: Keyword.get(opts, :items, [])
    }
  end
end
