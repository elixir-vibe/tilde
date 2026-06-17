defmodule Tilde.Core.Controller do
  @moduledoc """
  Transport-independent TUI input controller.

  SSH, tests, and future terminal transports can decode bytes into
  `Tilde.Core.Keys.key/0` values and apply them here.
  """

  alias Tilde.Command
  alias Tilde.Core.{Block, Input, Interaction, Keys, Session, Suggest}
  alias Tilde.Core.Interaction.Outcome

  @type result :: {:cont, Session.t()} | {:halt, Session.t()}
  @type interaction_result ::
          {:cont, Session.t(), [Outcome.t()]} | {:halt, Session.t(), [Outcome.t()]}

  @doc "Applies a transport-neutral interaction to a session."
  @spec apply_interaction(Session.t(), Interaction.t()) :: interaction_result()
  def apply_interaction(%Session{} = session, %Interaction{
        type: :toggle_expand,
        payload: %{id: id}
      })
      when is_binary(id) do
    continue(Session.toggle_expand(session, id))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :toggle_expand}) do
    {:cont, session} = apply_key(session, :toggle_expand)
    continue(session)
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :select_choice, payload: payload}) do
    continue(Session.select_choice(session, payload.block_id, payload.option_id))
  end

  def apply_interaction(%Session{} = session, %Interaction{
        type: :choice_action,
        payload: %{action_id: action_id}
      }) do
    continue(Session.put_status(session, "choice", action_id))
  end

  def apply_interaction(%Session{} = session, %Interaction{
        type: :input_changed,
        payload: %{input: input}
      }) do
    {:cont, session} = change_input(session, Input.put_value(session.input, input))
    continue(session)
  end

  def apply_interaction(%Session{} = session, %Interaction{
        type: :complete_input,
        payload: payload
      }) do
    input =
      Map.get(payload, :insert) || Command.completion(Map.get(payload, :input, "")) ||
        Map.get(payload, :input, "")

    {:cont, session} = change_input(session, Input.put_value(session.input, input))
    continue(session, completion_effect(payload, input))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :suggest_next}) do
    continue(Session.select_next_suggestion(session))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :suggest_previous}) do
    continue(Session.select_previous_suggestion(session))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :suggest_cancel}) do
    continue(Session.cancel_suggestions(session))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :suggest_accept}) do
    case Session.accept_suggestion(session) do
      {:ok, session} -> continue(session, [Outcome.complete_input(session.input.value)])
      :error -> continue(session)
    end
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :suggest_submit}) do
    submitted_input = selected_suggestion_completion(session)

    case Session.submit_suggestion(session) do
      {:ok, session} -> continue(session, submitted_suggestion_effects(submitted_input, session))
      :error -> continue(session)
    end
  end

  def apply_interaction(%Session{} = session, %Interaction{
        type: :submit,
        payload: %{input: input}
      }) do
    {:cont, session} = submit_input(%{session | input: Input.put_value(session.input, input)})
    continue(session, command_effects(input, session))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :interrupt}) do
    continue(Session.put_status(session, "runtime", "interrupted"))
  end

  def apply_interaction(%Session{} = session, %Interaction{type: :quit}) do
    {:halt, session, []}
  end

  @doc "Applies a decoded key to a session."
  @spec apply_key(Session.t(), Keys.key()) :: result()
  def apply_key(%Session{} = session, :toggle_expand) do
    case first_tool_id(session) do
      nil -> {:cont, session}
      id -> {:cont, Session.toggle_expand(session, id)}
    end
  end

  def apply_key(%Session{input: %Input{value: ""}} = session, :quit), do: {:halt, session}

  def apply_key(%Session{} = session, :quit),
    do: change_input(session, Input.insert(session.input, "q"))

  def apply_key(%Session{input: %Input{value: ""}} = session, :redraw), do: {:cont, session}

  def apply_key(%Session{} = session, :redraw),
    do: change_input(session, Input.insert(session.input, "r"))

  def apply_key(%Session{} = session, {:text, text}) do
    change_input(session, Input.insert(session.input, text))
  end

  def apply_key(%Session{} = session, key) when key in [:suggest_next, :down] do
    {:cont, Session.select_next_suggestion(session)}
  end

  def apply_key(%Session{} = session, key) when key in [:suggest_previous, :up, :backtab] do
    {:cont, Session.select_previous_suggestion(session)}
  end

  def apply_key(%Session{} = session, key) when key in [:tab, :suggest_accept] do
    case Session.accept_suggestion(session) do
      {:ok, session} -> {:cont, session}
      :error -> {:cont, session}
    end
  end

  def apply_key(%Session{} = session, :backspace) do
    change_input(session, Input.backspace(session.input))
  end

  def apply_key(%Session{} = session, :cancel) do
    if Session.command_suggestions(session) do
      {:cont, Session.cancel_suggestions(session)}
    else
      change_input(session, Input.clear(session.input))
    end
  end

  def apply_key(%Session{input: %Input{value: ""}} = session, :interrupt), do: {:halt, session}

  def apply_key(%Session{} = session, :interrupt) do
    change_input(session, Input.clear(session.input))
  end

  def apply_key(%Session{} = session, :enter) do
    case Session.submit_suggestion(session) do
      {:ok, session} ->
        {:cont, session}

      :error ->
        submit_input(session)
    end
  end

  def apply_key(%Session{} = session, _key), do: {:cont, session}

  defp submit_input(%Session{input: %Input{value: value}} = session) do
    if String.trim(value) == "" do
      {:cont, session}
    else
      {:cont, Session.append_event(session, Tilde.input_submitted(value))}
    end
  end

  defp change_input(%Session{} = session, %Input{} = input) do
    event = Tilde.input_changed(input.value, metadata: %{cursor: input.cursor})
    {:cont, Session.append_event(session, event)}
  end

  defp first_tool_id(%Session{} = session) do
    Enum.find_value(session.transcript.blocks, fn
      %Block{kind: :tool, id: id} -> id
      _block -> nil
    end)
  end

  defp selected_suggestion_completion(%Session{} = session) do
    case Session.command_suggestions(session) do
      %Suggest{} = suggest -> Suggest.accept(suggest)
      nil -> nil
    end
  end

  defp submitted_suggestion_effects(nil, _session), do: []

  defp submitted_suggestion_effects(input, %Session{} = session) when is_binary(input) do
    if String.ends_with?(input, " ") do
      [Outcome.complete_input(session.input.value)]
    else
      [Outcome.complete_input(session.input.value) | command_effects(input, session)]
    end
  end

  defp command_effects(input, %Session{} = session) do
    case Command.parse(input) do
      {:ok, command} -> command |> Command.run(session, []) |> Outcome.from_command_effects()
      :error -> []
    end
  end

  defp completion_effect(%{insert: insert}, input) when insert != input,
    do: [Outcome.complete_input(input)]

  defp completion_effect(%{input: input}, completed) when input != completed,
    do: [Outcome.complete_input(completed)]

  defp completion_effect(_payload, _input), do: []

  defp continue(%Session{} = session, effects \\ []), do: {:cont, session, effects}
end
