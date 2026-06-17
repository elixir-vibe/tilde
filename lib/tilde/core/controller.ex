defmodule Tilde.Core.Controller do
  @moduledoc """
  Transport-independent TUI input controller.

  SSH, tests, and future terminal transports can decode bytes into
  `Tilde.Core.Keys.key/0` values and apply them here.
  """

  alias Tilde.Core.{Block, Input, Session}
  alias Tilde.Core.Keys

  @type result :: {:cont, Session.t()} | {:halt, Session.t()}

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
end
