defmodule Tilde.Core.Input do
  @moduledoc """
  Semantic console input state.

  Input is part of session state rather than terminal or DOM state. Renderers can
  display the value and cursor however they need without making a textarea,
  PTY, or character grid canonical.
  """

  @type mode :: :compose

  @type t :: %__MODULE__{
          value: String.t(),
          cursor: non_neg_integer(),
          mode: mode()
        }

  defstruct value: "", cursor: 0, mode: :compose

  @doc "Creates input state."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    value = Keyword.get(opts, :value, "")

    %__MODULE__{
      value: value,
      cursor: Keyword.get(opts, :cursor, String.length(value)),
      mode: Keyword.get(opts, :mode, :compose)
    }
  end

  @doc "Replaces the input value and moves the cursor to the end by default."
  @spec put_value(t(), String.t(), keyword()) :: t()
  def put_value(%__MODULE__{} = input, value, opts \\ []) when is_binary(value) do
    %{input | value: value, cursor: Keyword.get(opts, :cursor, String.length(value))}
  end

  @doc "Inserts text at the current cursor."
  @spec insert(t(), String.t()) :: t()
  def insert(%__MODULE__{} = input, text) when is_binary(text) do
    {left, right} = split_at_cursor(input)
    value = left <> text <> right
    %{input | value: value, cursor: input.cursor + String.length(text)}
  end

  @doc "Deletes one character before the cursor."
  @spec backspace(t()) :: t()
  def backspace(%__MODULE__{cursor: 0} = input), do: input

  def backspace(%__MODULE__{} = input) do
    {left, right} = split_at_cursor(input)
    left = left |> String.graphemes() |> Enum.drop(-1) |> Enum.join()
    %{input | value: left <> right, cursor: input.cursor - 1}
  end

  @doc "Clears the input value."
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = input), do: %{input | value: "", cursor: 0}

  defp split_at_cursor(%__MODULE__{} = input) do
    graphemes = String.graphemes(input.value)
    {left, right} = Enum.split(graphemes, input.cursor)
    {Enum.join(left), Enum.join(right)}
  end
end
