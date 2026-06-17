defmodule Tilde.Core.Index do
  @moduledoc "Semantic console index state and behavior."

  alias Tilde.Command
  alias Tilde.Core.{Input, Interaction, Suggest}
  alias Tilde.Core.Interaction.Effect
  alias Tilde.Session.Summary

  @type t :: %__MODULE__{
          input: Input.t(),
          session_suggest: Suggest.t() | nil,
          command_suggest: Suggest.t() | nil
        }

  defstruct input: %Input{}, session_suggest: nil, command_suggest: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{input: Keyword.get(opts, :input, %Input{})}
    |> put_session_suggestions()
    |> put_command_suggestions()
  end

  @spec refresh(t()) :: t()
  def refresh(%__MODULE__{} = index), do: put_session_suggestions(index)

  @spec input_changed(t(), String.t()) :: t()
  def input_changed(%__MODULE__{} = index, value) when is_binary(value) do
    %{index | input: %Input{value: value, cursor: String.length(value)}}
    |> put_command_suggestions()
  end

  @spec new_shortcut(t()) :: t()
  def new_shortcut(%__MODULE__{} = index), do: input_changed(index, "/new ")

  @type interaction_result :: {:cont, t(), [Effect.t()]} | {:halt, t(), [Effect.t()]}

  @spec apply_interaction(t(), Interaction.t()) :: interaction_result()
  def apply_interaction(%__MODULE__{} = index, %Interaction{
        type: :input_changed,
        payload: %{input: input}
      }) do
    continue(input_changed(index, input))
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{
        type: :complete_input,
        payload: %{insert: insert}
      }) do
    case session_id_for_insert(index, insert) do
      nil -> continue(input_changed(index, insert), [Effect.complete_input(insert)])
      session_id -> continue(index, [Effect.open_session(session_id)])
    end
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :suggest_next}) do
    continue(select_next(index))
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :suggest_previous}) do
    continue(select_previous(index))
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :suggest_cancel}) do
    continue(cancel_suggestions(index))
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :suggest_accept}) do
    case accept_suggestion(index) do
      {:ok, index} -> continue(index, [Effect.complete_input(index.input.value)])
      :error -> continue(index)
    end
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :suggest_submit}) do
    submit_suggestion(index)
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{
        type: :submit,
        payload: %{input: input}
      }) do
    submit_input(index, input)
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :interrupt}) do
    index = input_changed(index, "")
    continue(index, [Effect.complete_input("")])
  end

  def apply_interaction(%__MODULE__{} = index, %Interaction{type: :new_shortcut}) do
    index = new_shortcut(index)
    continue(index, [Effect.complete_input(index.input.value)])
  end

  @spec accept_suggestion(t()) :: {:ok, t()} | :error
  def accept_suggestion(%__MODULE__{} = index) do
    case active_suggestions(index) do
      %Suggest{} = suggest ->
        case Suggest.accept(suggest) do
          nil -> :error
          insert -> {:ok, input_changed(index, insert)}
        end

      nil ->
        :error
    end
  end

  @spec selected_session_id(t()) :: String.t() | nil
  def selected_session_id(%__MODULE__{} = index) do
    case index.session_suggest do
      %Suggest{} = suggest -> selected_session_id(suggest)
      nil -> nil
    end
  end

  @spec selected_session_id(Suggest.t()) :: String.t() | nil
  def selected_session_id(%Suggest{} = suggest) do
    case Suggest.selected(suggest) do
      %{metadata: %{session_id: id}} when is_binary(id) -> id
      %{id: id} when is_binary(id) -> id
      _item -> nil
    end
  end

  @spec select_next(t()) :: t()
  def select_next(%__MODULE__{} = index), do: update_active_suggestions(index, &Suggest.next/1)

  @spec select_previous(t()) :: t()
  def select_previous(%__MODULE__{} = index),
    do: update_active_suggestions(index, &Suggest.previous/1)

  @spec cancel_suggestions(t()) :: t()
  def cancel_suggestions(%__MODULE__{} = index), do: %{index | command_suggest: nil}

  @spec command_suggestions(t()) :: Suggest.t() | nil
  def command_suggestions(%__MODULE__{} = index), do: index.command_suggest

  @spec session_suggestions(t()) :: Suggest.t() | nil
  def session_suggestions(%__MODULE__{} = index), do: index.session_suggest

  defp put_session_suggestions(%__MODULE__{} = index) do
    items =
      Summary.list()
      |> Enum.map(&Summary.to_suggest_item/1)

    suggest =
      if items == [] do
        nil
      else
        Suggest.new(id: "session-index", title: "sessions  first → last", items: items)
      end

    %{index | session_suggest: suggest}
  end

  defp put_command_suggestions(%__MODULE__{} = index) do
    previous_id = index.command_suggest && index.command_suggest.selected_id

    command_suggest =
      case Command.suggestions(index.input.value) do
        nil -> nil
        suggest -> Suggest.select_id(suggest, previous_id)
      end

    %{index | command_suggest: command_suggest}
  end

  defp active_suggestions(%__MODULE__{} = index),
    do: index.command_suggest || index.session_suggest

  defp update_active_suggestions(%__MODULE__{} = index, fun) do
    cond do
      index.command_suggest -> %{index | command_suggest: fun.(index.command_suggest)}
      index.session_suggest -> %{index | session_suggest: fun.(index.session_suggest)}
      true -> index
    end
  end

  defp submit_suggestion(%__MODULE__{} = index) do
    cond do
      command_suggestions(index) ->
        submit_command_suggestion(index)

      session_id = selected_session_id(index) ->
        continue(index, [Effect.open_session(session_id)])

      true ->
        continue(index)
    end
  end

  defp submit_command_suggestion(%__MODULE__{} = index) do
    case accept_suggestion(index) do
      {:ok, %__MODULE__{input: %{value: input}} = index} ->
        if String.ends_with?(input, " ") do
          continue(index, [Effect.complete_input(input)])
        else
          submit_input(index, input)
        end

      :error ->
        continue(index)
    end
  end

  defp submit_input(%__MODULE__{} = index, input) do
    input
    |> Command.parse()
    |> case do
      {:ok, %Command{} = command} ->
        command
        |> Command.run(Tilde.session(id: "index"), [])
        |> index_command_effects(index)

      :error ->
        continue(index)
    end
  end

  defp index_command_effects(effects, %__MODULE__{} = index) do
    Enum.reduce(effects, continue(index), fn
      %Tilde.Command.Effect.AttachSession{id: id}, {:cont, index, effects} ->
        {:cont, index, [Effect.open_session(id) | effects]}

      %Tilde.Command.Effect.NewSession{id: id}, {:cont, index, effects} ->
        {:cont, index, [Effect.open_session(id) | effects]}

      %Tilde.Command.Effect.DetachSession{}, {:cont, index, effects} ->
        {:cont, index, effects}

      _effect, result ->
        result
    end)
    |> normalize_effect_order()
  end

  defp session_id_for_insert(%__MODULE__{} = index, insert) do
    case session_suggestions(index) do
      nil -> nil
      suggest -> Enum.find_value(suggest.items, &session_id_for_insert(&1, insert))
    end
  end

  defp session_id_for_insert(%{insert: insert, metadata: %{session_id: id}}, insert), do: id
  defp session_id_for_insert(_item, _insert), do: nil

  defp continue(%__MODULE__{} = index, effects \\ []), do: {:cont, index, effects}

  defp normalize_effect_order({:cont, index, effects}), do: {:cont, index, Enum.reverse(effects)}
end
