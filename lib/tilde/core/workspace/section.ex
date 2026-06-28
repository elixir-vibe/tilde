defmodule Tilde.Core.Workspace.Section do
  @moduledoc """
  Renderer-neutral section of relevant workspace files.

  Sections preserve why files are shown, while `tree` provides the nested
  path-natural presentation shared by Live and terminal renderers.
  """

  alias Tilde.Core.Workspace.File
  alias Tilde.Core.Workspace.TreeNode

  defstruct title: "", files: [], tree: []

  @type t :: %__MODULE__{
          title: String.t(),
          files: [File.t()],
          tree: [TreeNode.t()]
        }

  @doc "Builds a workspace file section."
  @spec new(keyword()) :: t()
  def new(opts) do
    %__MODULE__{
      title: Keyword.fetch!(opts, :title),
      files: Keyword.get(opts, :files, []),
      tree: Keyword.get(opts, :tree, [])
    }
  end
end
