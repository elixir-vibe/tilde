defmodule Tilde.Tool.View.Segment do
  @moduledoc "A styled segment in a compact tool call view."

  @type color :: :accent | :muted | :dim | :success
  @type t :: %__MODULE__{text: String.t(), color: color() | nil}

  defstruct text: "", color: nil

  @spec new(String.t(), keyword()) :: t()
  def new(text, opts \\ []) do
    %__MODULE__{text: to_string(text), color: Keyword.get(opts, :color)}
  end
end
