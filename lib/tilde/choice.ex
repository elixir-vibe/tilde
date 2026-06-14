defmodule Tilde.Choice do
  @moduledoc """
  Semantic choice/approval state for interactive console blocks.

  This is the core counterpart to pi-style option pickers. Renderers may expose
  choices as keyboard lists, buttons, forms, or accessible web controls.
  """

  alias Tilde.Action

  @type option :: %{
          required(:id) => String.t(),
          required(:label) => String.t(),
          optional(:description) => String.t(),
          optional(:metadata) => map()
        }
  @type option_input :: option() | {term(), term()} | {term(), term(), term()}

  @type t :: %__MODULE__{
          question: String.t(),
          options: [option()],
          selected: [String.t()],
          allow_multiple?: boolean(),
          actions: [Action.t()],
          metadata: map()
        }

  defstruct question: "",
            options: [],
            selected: [],
            allow_multiple?: false,
            actions: [],
            metadata: %{}

  @doc "Creates choice state."
  @spec new(String.t(), [option_input()], keyword()) :: t()
  def new(question, options, opts \\ []) when is_binary(question) and is_list(options) do
    %__MODULE__{
      question: question,
      options: normalize_options(options),
      selected: Keyword.get(opts, :selected, []),
      allow_multiple?: Keyword.get(opts, :allow_multiple?, false),
      actions: Keyword.get(opts, :actions, default_actions()),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc "Selects an option according to single/multiple mode."
  @spec select(t(), String.t()) :: t()
  def select(%__MODULE__{allow_multiple?: false} = choice, id) when is_binary(id) do
    %{choice | selected: [id]}
  end

  def select(%__MODULE__{allow_multiple?: true} = choice, id) when is_binary(id) do
    selected =
      if id in choice.selected,
        do: List.delete(choice.selected, id),
        else: choice.selected ++ [id]

    %{choice | selected: selected}
  end

  defp normalize_options(options) do
    Enum.map(options, fn
      %{id: id, label: label} = option ->
        option
        |> Map.put(:id, to_string(id))
        |> Map.put(:label, to_string(label))

      {id, label, description} ->
        %{id: to_string(id), label: to_string(label), description: to_string(description)}

      {id, label} ->
        %{id: to_string(id), label: to_string(label)}
    end)
  end

  defp default_actions do
    [
      Action.new(:confirm, "Confirm", kind: :primary, key: "enter"),
      Action.new(:cancel, "Cancel", key: "escape")
    ]
  end
end
