defmodule Tilde.Core.Review.File do
  @moduledoc """
  Renderer-neutral review state for a single workspace file.
  """

  alias Tilde.Core.Review.Comment

  defstruct path: "", status: :pending, comments: []

  @type status :: :pending | :reviewed | :needs_changes | :approved

  @type t :: %__MODULE__{
          path: String.t(),
          status: status(),
          comments: [Comment.t()]
        }

  @doc "Builds a reviewed file entry."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      path: Keyword.fetch!(opts, :path),
      status: Keyword.get(opts, :status, :pending),
      comments: Keyword.get(opts, :comments, [])
    }
  end
end
