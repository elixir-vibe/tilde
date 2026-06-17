defmodule TildeTest.Driver do
  @moduledoc "Shared user-behavior test driver API for Tilde transports."

  import ExUnit.Assertions

  @type state :: struct()
  @type key :: :up | :down | :tab | :backtab | :enter | :escape | :ctrl_o | atom()

  @callback open(keyword()) :: state()
  @callback type(state(), String.t()) :: state()
  @callback press(state(), key()) :: state()
  @callback text(state()) :: String.t()
  @callback session(state()) :: Tilde.Core.Session.t()

  @doc "Types text through a driver."
  def type(driver, state, text), do: driver.type(state, text)

  @doc "Presses a semantic key through a driver."
  def press(driver, state, key), do: driver.press(state, key)

  @doc "Returns transport-visible text."
  def text(driver, state), do: driver.text(state)

  @doc "Returns the canonical semantic session."
  def session(driver, state), do: driver.session(state)

  @doc "Asserts the current input draft."
  def assert_input(driver, state, expected) do
    actual = session(driver, state).input.value
    assert actual == expected
    state
  end

  @doc "Asserts rendered transport text contains a string or regex."
  def assert_text(driver, state, expected) do
    assert text(driver, state) =~ expected
    state
  end

  @doc "Refutes rendered transport text contains a string or regex."
  def refute_text(driver, state, unexpected) do
    refute text(driver, state) =~ unexpected
    state
  end

  @doc "Asserts a command suggestion exists and optionally whether it is selected."
  def assert_suggestion(driver, state, label, opts \\ []) do
    selected? = Keyword.get(opts, :selected?)
    suggest = session(driver, state) |> Tilde.Core.Session.command_suggestions()

    assert %Tilde.Core.Suggest{} = suggest
    index = Enum.find_index(suggest.items, &(&1.label == label))
    assert is_integer(index), "expected suggestion #{inspect(label)}"

    case selected? do
      true -> assert suggest.selected_index == index
      false -> refute suggest.selected_index == index
      nil -> :ok
    end

    state
  end
end
