defmodule Tilde.Run do
  @moduledoc """
  Inline semantic text run.

  Runs model text marks such as bold, underline, code, muted, or link without
  committing to Markdown, HTML, ANSI, or any other renderer.
  """

  @type mark ::
          :bold | :italic | :underline | :strike | :code | :muted | :accent | :error | :success

  @type t :: %__MODULE__{
          text: String.t(),
          marks: [mark()],
          attrs: map()
        }

  defstruct text: "", marks: [], attrs: %{}

  @doc "Creates a text run."
  @spec new(String.t(), [mark()], map()) :: t()
  def new(text, marks \\ [], attrs \\ %{}) when is_binary(text) and is_list(marks) do
    %__MODULE__{text: text, marks: marks, attrs: attrs}
  end
end
