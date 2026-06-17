defmodule TildeTest.SessionAssertions do
  @moduledoc "ExUnit assertions for semantic Tilde session state."

  import ExUnit.Assertions

  alias Tilde.Core.{AssistantTurn, Session}

  @doc "Asserts the session assistant turn is in the expected phase."
  @spec assert_assistant_phase(Session.t(), AssistantTurn.phase()) :: Session.t()
  def assert_assistant_phase(%Session{} = session, phase) when is_atom(phase) do
    assert %AssistantTurn{phase: ^phase} = session.assistant
    session
  end

  @doc "Receives and returns a session update with the expected assistant phase."
  defmacro assert_receive_phase(session_id, phase, timeout \\ 100) do
    quote do
      expected_session_id = unquote(session_id)
      expected_phase = unquote(phase)

      assert_receive {:tilde_session_updated, ^expected_session_id,
                      %Tilde.Core.Session{
                        assistant: %Tilde.Core.AssistantTurn{phase: ^expected_phase}
                      } = session},
                     unquote(timeout)

      session
    end
  end

  @doc "Refutes receiving a session update with the given assistant phase."
  defmacro refute_receive_phase(session_id, phase, timeout \\ 100) do
    quote do
      expected_session_id = unquote(session_id)
      expected_phase = unquote(phase)

      refute_receive {:tilde_session_updated, ^expected_session_id,
                      %Tilde.Core.Session{
                        assistant: %Tilde.Core.AssistantTurn{phase: ^expected_phase}
                      }},
                     unquote(timeout)
    end
  end

  @doc "Asserts the session is waiting for first assistant output."
  @spec assert_assistant_waiting(Session.t()) :: Session.t()
  def assert_assistant_waiting(%Session{} = session) do
    assert Session.assistant_waiting?(session)
    session
  end

  @doc "Refutes that the session is waiting for first assistant output."
  @spec refute_assistant_waiting(Session.t()) :: Session.t()
  def refute_assistant_waiting(%Session{} = session) do
    refute Session.assistant_waiting?(session)
    session
  end

  @doc "Asserts the session has an active assistant turn."
  @spec assert_assistant_active(Session.t()) :: Session.t()
  def assert_assistant_active(%Session{} = session) do
    assert Session.assistant_active?(session)
    session
  end

  @doc "Refutes that the session has an active assistant turn."
  @spec refute_assistant_active(Session.t()) :: Session.t()
  def refute_assistant_active(%Session{} = session) do
    refute Session.assistant_active?(session)
    session
  end
end
