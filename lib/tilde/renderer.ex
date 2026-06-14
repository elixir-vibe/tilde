defmodule Tilde.Renderer do
  @moduledoc """
  Behaviour for renderers that consume semantic Tilde structures.
  """

  alias Tilde.Transcript

  @callback render(Transcript.t(), keyword()) :: term()
end
