defmodule Tilde.Core.Dialog do
  @moduledoc """
  Semantic dialog content for overlay-style UI.

  Dialogs are transport-neutral. Renderers decide whether to show them as a
  modal web panel, a terminal box, or another appropriate affordance.
  """

  @type t :: %__MODULE__{
          title: String.t(),
          body: String.t(),
          modal?: boolean()
        }

  defstruct title: "", body: "", modal?: true

  @doc "Creates semantic dialog content."
  @spec new(String.t(), String.t(), keyword()) :: t()
  def new(title, body, opts \\ []) when is_binary(title) and is_binary(body) do
    %__MODULE__{title: title, body: body, modal?: Keyword.get(opts, :modal?, true)}
  end
end
