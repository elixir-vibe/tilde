defmodule Tilde.View.Text do
  @moduledoc """
  Styled inline text for shared renderer-neutral view lines.
  """

  defstruct text: "", style: :plain

  @type style ::
          :plain | :title | :accent | :muted | :primary | :success | :error | :warning | :shortcut
  @type t :: %__MODULE__{text: String.t(), style: style()}

  @spec new(term(), style()) :: t()
  def new(text, style \\ :plain), do: %__MODULE__{text: to_string(text), style: style}
end
