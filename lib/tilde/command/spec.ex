defmodule Tilde.Command.Spec do
  @moduledoc "A slash command's registry metadata."

  @type t :: %__MODULE__{label: String.t(), insert: String.t(), description: String.t()}

  defstruct label: "", insert: "", description: ""

  @spec new(String.t(), String.t(), String.t()) :: t()
  def new(label, insert, description) do
    %__MODULE__{label: label, insert: insert, description: description}
  end
end
