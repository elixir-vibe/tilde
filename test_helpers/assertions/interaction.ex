defmodule TildeTest.InteractionAssertions do
  @moduledoc "Assertions for transport-neutral interaction results."

  import ExUnit.Assertions

  alias Tilde.Core.{Index, Session}
  alias Tilde.Core.Interaction.Outcome

  @type result ::
          {:cont, Index.t() | Session.t(), [Outcome.t()]}
          | {:halt, Index.t() | Session.t(), [Outcome.t()]}

  @spec assert_interaction_cont(result()) :: result()
  def assert_interaction_cont({:cont, _state, _outcomes} = result), do: result

  def assert_interaction_cont(other) do
    flunk("expected interaction to continue, got: #{inspect(other)}")
  end

  @spec assert_interaction_halt(result()) :: result()
  def assert_interaction_halt({:halt, _state, _outcomes} = result), do: result

  def assert_interaction_halt(other) do
    flunk("expected interaction to halt, got: #{inspect(other)}")
  end

  @spec assert_outcome(result(), atom(), keyword()) :: result()
  def assert_outcome({_status, _state, outcomes} = result, type, attrs \\ []) when is_atom(type) do
    assert Enum.any?(outcomes, &outcome_matches?(&1, type, attrs)),
           "expected outcome #{inspect(type)} with #{inspect(attrs)}, got: #{inspect(outcomes)}"

    result
  end

  @spec refute_outcome(result(), atom(), keyword()) :: result()
  def refute_outcome({_status, _state, outcomes} = result, type, attrs \\ []) when is_atom(type) do
    refute Enum.any?(outcomes, &outcome_matches?(&1, type, attrs)),
           "did not expect outcome #{inspect(type)} with #{inspect(attrs)}, got: #{inspect(outcomes)}"

    result
  end

  @spec assert_interaction_input(result(), String.t()) :: result()
  def assert_interaction_input({_status, %{input: %{value: value}}, _outcomes} = result, expected) do
    assert value == expected
    result
  end

  def assert_interaction_input(other, _expected) do
    flunk("expected interaction state with input, got: #{inspect(other)}")
  end

  defp outcome_matches?(%Outcome{type: type, payload: payload}, type, attrs) do
    Enum.all?(attrs, fn {key, value} -> Map.get(payload, key) == value end)
  end

  defp outcome_matches?(_outcome, _type, _attrs), do: false
end
