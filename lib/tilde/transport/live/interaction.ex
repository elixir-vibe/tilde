defmodule Tilde.Transport.Live.Interaction do
  @moduledoc "Translates LiveView event names and params into core interactions."

  alias Tilde.Core.{Index, Input, Interaction}

  @spec index(String.t(), map(), Index.t()) :: Interaction.t() | nil
  def index("tilde:input_changed", %{"input" => "n"}, %Index{input: %Input{value: ""}}),
    do: Interaction.new(:new_shortcut)

  def index("tilde:input_changed", %{"input" => input}, %Index{}),
    do: Interaction.input_changed(input)

  def index("tilde:complete_input", %{"insert" => insert}, %Index{}),
    do: Interaction.complete_input(insert)

  def index("tilde:suggest_next", _params, %Index{}), do: Interaction.new(:suggest_next)
  def index("tilde:suggest_previous", _params, %Index{}), do: Interaction.new(:suggest_previous)
  def index("tilde:suggest_cancel", _params, %Index{}), do: Interaction.new(:suggest_cancel)
  def index("tilde:suggest_accept", _params, %Index{}), do: Interaction.new(:suggest_accept)
  def index("tilde:suggest_submit", _params, %Index{}), do: Interaction.new(:suggest_submit)
  def index("tilde:submit", %{"input" => input}, %Index{}), do: Interaction.submit(input)
  def index("tilde:interrupt", _params, %Index{}), do: Interaction.new(:interrupt)
  def index("tilde:index_new", _params, %Index{}), do: Interaction.new(:new_shortcut)

  def index("tilde:index_keydown", %{"key" => "Enter"}, %Index{}),
    do: Interaction.new(:suggest_submit)

  def index("tilde:index_keydown", %{"key" => "n", "value" => ""}, %Index{}),
    do: Interaction.new(:new_shortcut)

  def index(_event, _params, %Index{}), do: nil

  @spec session(String.t(), map()) :: Interaction.t() | nil
  def session("tilde:toggle_expand", %{"id" => id}),
    do: Interaction.new(:toggle_expand, %{id: id})

  def session("tilde:toggle_expand", _params), do: Interaction.new(:toggle_expand)

  def session("tilde:select_choice", %{"block-id" => block_id, "option-id" => option_id}) do
    Interaction.new(:select_choice, %{block_id: block_id, option_id: option_id})
  end

  def session("tilde:choice_action", %{"action-id" => action_id}),
    do: Interaction.new(:choice_action, %{action_id: action_id})

  def session("tilde:dialog_action", %{"widget-id" => widget_id, "action-id" => action_id}) do
    Interaction.new(:dialog_action, %{widget_id: widget_id, action_id: action_id})
  end

  def session("tilde:input_changed", %{"input" => input}), do: Interaction.input_changed(input)

  def session("tilde:complete_input", params) do
    Interaction.new(:complete_input, %{
      input: Map.get(params, "input", ""),
      insert: Map.get(params, "insert")
    })
  end

  def session("tilde:suggest_next", _params), do: Interaction.new(:suggest_next)
  def session("tilde:suggest_previous", _params), do: Interaction.new(:suggest_previous)
  def session("tilde:suggest_cancel", _params), do: Interaction.new(:suggest_cancel)
  def session("tilde:suggest_accept", _params), do: Interaction.new(:suggest_accept)
  def session("tilde:suggest_submit", _params), do: Interaction.new(:suggest_submit)
  def session("tilde:submit", %{"input" => input}), do: Interaction.submit(input)
  def session("tilde:interrupt", _params), do: Interaction.new(:interrupt)
  def session(_event, _params), do: nil
end
