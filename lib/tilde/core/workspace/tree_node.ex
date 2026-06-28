defmodule Tilde.Core.Workspace.TreeNode do
  @moduledoc """
  Renderer-neutral node in a relevant workspace file tree.

  Directory nodes provide structure for the subset of files relevant to the
  current session. File nodes carry the original `Tilde.Core.Workspace.File`
  entry so renderers keep status marks, selection, and full paths.
  """

  alias Tilde.Core.Workspace.File

  defstruct name: "", path: "", kind: :directory, children: [], file: nil

  @type kind :: :directory | :file

  @type t :: %__MODULE__{
          name: String.t(),
          path: String.t(),
          kind: kind(),
          children: [t()],
          file: File.t() | nil
        }

  @doc "Builds a tree node."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      path: Keyword.fetch!(opts, :path),
      kind: Keyword.get(opts, :kind, :directory),
      children: Keyword.get(opts, :children, []),
      file: Keyword.get(opts, :file)
    }
  end
end
