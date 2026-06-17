defmodule Tilde.Transport.SSH.LocalPrompt do
  @moduledoc "Local prompt behavior for SSH clients attached to shared sessions."

  alias Tilde.Core.{Controller, Input, Session}
  alias Tilde.Session.Server, as: SessionServer

  @type state :: %{session: Session.t()}
  @type result :: {:cont, {:cont, state()}} | {:halt, {:halt, state()}}

  @spec apply_key(state(), Tilde.Core.Keys.key()) :: result()
  def apply_key(%{session: %Session{}} = state, :quit) do
    if state.session.input.value == "" do
      {:halt, {:halt, state}}
    else
      put_input(state, Input.insert(state.session.input, "q"))
    end
  end

  def apply_key(%{session: %Session{}} = state, :redraw) do
    if state.session.input.value == "" do
      {:cont, {:cont, state}}
    else
      put_input(state, Input.insert(state.session.input, "r"))
    end
  end

  def apply_key(%{session: %Session{}} = state, {:text, text}) do
    put_input(state, Input.insert(state.session.input, text))
  end

  def apply_key(%{session: %Session{}} = state, key) when key in [:tab, :backtab, :up, :down] do
    {:cont, session} = Controller.apply_key(state.session, key)
    {:cont, {:cont, %{state | session: session}}}
  end

  def apply_key(%{session: %Session{}} = state, :backspace) do
    put_input(state, Input.backspace(state.session.input))
  end

  def apply_key(%{session: %Session{}} = state, :cancel) do
    {:cont, session} = Controller.apply_key(state.session, :cancel)
    {:cont, {:cont, %{state | session: session}}}
  end

  def apply_key(%{session: %Session{}} = state, :interrupt) do
    if state.session.input.value == "" do
      {:halt, {:halt, state}}
    else
      put_input(state, Input.clear(state.session.input))
    end
  end

  def apply_key(%{session: %Session{}} = state, :toggle_expand) do
    {:cont, session} = Controller.apply_key(state.session, :toggle_expand)
    {:cont, {:cont, %{state | session: session}}}
  end

  def apply_key(%{session: %Session{}} = state, _key), do: {:cont, {:cont, state}}

  @spec submit(SessionServer.name(), state()) :: {:cont, {:cont, state()}}
  def submit(server, %{session: %Session{input: %Input{value: value}}} = state) do
    if String.trim(value) == "" do
      {:cont, {:cont, state}}
    else
      session =
        SessionServer.update_session(
          server,
          &Session.append_event(&1, Tilde.input_submitted(value))
        )

      {:cont, {:cont, %{state | session: session}}}
    end
  end

  @spec preserve(Session.t(), Session.t() | nil) :: Session.t()
  def preserve(%Session{} = incoming, %Session{input: %Input{value: value}} = current)
      when value != "" do
    %{incoming | input: current.input, widgets: current.widgets}
  end

  def preserve(%Session{} = incoming, _current), do: incoming

  defp put_input(%{session: %Session{}} = state, %Input{} = input) do
    session =
      Session.append_event(
        state.session,
        Tilde.input_changed(input.value, metadata: %{cursor: input.cursor})
      )

    {:cont, {:cont, %{state | session: session}}}
  end
end
