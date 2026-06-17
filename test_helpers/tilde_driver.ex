defmodule TildeTest.Driver do
  @moduledoc "Shared pipeline-friendly user-behavior test driver API for Tilde transports."

  import ExUnit.Assertions

  @type state :: struct()
  @type key :: :up | :down | :tab | :backtab | :enter | :escape | :ctrl_o | atom()

  @callback open(keyword()) :: state()
  @callback type(state(), String.t()) :: state()
  @callback press(state(), key()) :: state()
  @callback text(state()) :: String.t()
  @callback session(state()) :: Tilde.Core.Session.t()

  @doc "Opens a transport driver."
  @spec open(module(), keyword()) :: state()
  def open(driver, opts \\ []), do: driver.open(opts)

  @doc "Labels a user step while preserving pipeline flow."
  @spec step(state(), String.t(), (state() -> state())) :: state()
  def step(state, label, fun) when is_binary(label) and is_function(fun, 1) do
    try do
      fun.(state)
    rescue
      error ->
        reraise ExUnit.AssertionError,
                [message: "step failed: #{label}\n#{Exception.message(error)}"],
                __STACKTRACE__
    end
  end

  @doc "Types text through a driver."
  @spec type(state(), String.t()) :: state()
  def type(state, text), do: driver(state).type(state, text)

  @doc "Presses a semantic key through a driver."
  @spec press(state(), key()) :: state()
  def press(state, key), do: driver(state).press(state, key)

  @doc "Returns transport-visible text."
  @spec text(state()) :: String.t()
  def text(state), do: driver(state).text(state)

  @doc "Returns the canonical semantic session."
  @spec session(state()) :: Tilde.Core.Session.t()
  def session(state), do: driver(state).session(state)

  @doc "Asserts the current input draft."
  @spec assert_input(state(), String.t()) :: state()
  def assert_input(state, expected) do
    actual = session(state).input.value
    assert actual == expected
    state
  end

  @doc "Asserts rendered transport text contains a string or regex."
  @spec assert_text(state(), String.t() | Regex.t()) :: state()
  def assert_text(state, expected) do
    assert text(state) =~ expected
    state
  end

  @doc "Refutes rendered transport text contains a string or regex."
  @spec refute_text(state(), String.t() | Regex.t()) :: state()
  def refute_text(state, unexpected) do
    refute text(state) =~ unexpected
    state
  end

  @doc "Asserts a command suggestion exists and optionally whether it is selected."
  @spec assert_suggestion(state(), String.t(), keyword()) :: state()
  def assert_suggestion(state, label, opts \\ []) do
    selected? = Keyword.get(opts, :selected?)
    suggest = session(state) |> Tilde.Core.Session.command_suggestions()

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

  @doc "Refutes that command suggestions are visible."
  @spec refute_suggestions(state()) :: state()
  def refute_suggestions(state) do
    assert is_nil(session(state) |> Tilde.Core.Session.command_suggestions())
    state
  end

  @doc "Returns the transport module for a driver state."
  @spec driver(state()) :: module()
  def driver(%module{}), do: module
end
