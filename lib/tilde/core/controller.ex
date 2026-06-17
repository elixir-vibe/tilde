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

  def apply_key(%Session{} = session, :tab) do
    case Tilde.Command.completion(session.input.value) do
      nil -> {:cont, session}
      completion -> change_input(session, Input.put_value(session.input, completion))
    end
  end

  def apply_key(%Session{} = session, :backspace) do
    change_input(session, Input.backspace(session.input))
  end

  def apply_key(%Session{} = session, :cancel) do
    change_input(session, Input.clear(session.input))
  end

  def apply_key(%Session{input: %Input{value: ""}} = session, :interrupt), do: {:halt, session}

  def apply_key(%Session{} = session, :interrupt) do
    change_input(session, Input.clear(session.input))
  end

  def apply_key(%Session{input: %Input{value: value}} = session, :enter) do
    if String.trim(value) == "" do
      {:cont, session}
    else
      {:cont, Session.append_event(session, Tilde.input_submitted(value))}
    end
  end

  def apply_key(%Session{} = session, _key), do: {:cont, session}

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
