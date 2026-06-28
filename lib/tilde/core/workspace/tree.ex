defmodule Tilde.Core.Workspace.Tree do
  @moduledoc """
  Builds a path-natural tree for relevant workspace files.

  The tree only contains files provided by the caller. It does not scan the
  repository and does not invent clean sibling files. Sibling order follows
  path-natural order from sorted full path segments rather than forcing
  directories before files.
  """

  alias Tilde.Core.Workspace.File
  alias Tilde.Core.Workspace.TreeNode

  @doc "Builds root tree nodes from workspace files."
  @spec from_files([File.t()]) :: [TreeNode.t()]
  def from_files(files) when is_list(files) do
    files
    |> Enum.sort_by(&path_parts/1)
    |> Enum.reduce([], fn %File{} = file, roots ->
      insert(roots, path_parts(file), file, nil)
    end)
  end

  defp path_parts(%File{path: path}) do
    path
    |> Path.split()
    |> Enum.reject(&(&1 == ""))
  end

  defp insert(nodes, [], _file, _parent_path), do: nodes

  defp insert(nodes, [name], %File{} = file, parent_path) do
    path = child_path(parent_path, name)
    node = TreeNode.new(name: name, path: path, kind: :file, file: file)
    upsert(nodes, node)
  end

  defp insert(nodes, [name | rest], %File{} = file, parent_path) do
    path = child_path(parent_path, name)

    node =
      case Enum.find(nodes, &(&1.name == name and &1.kind == :directory)) do
        %TreeNode{} = node -> node
        nil -> TreeNode.new(name: name, path: path, kind: :directory)
      end

    updated = %{node | children: insert(node.children, rest, file, path)}
    upsert(nodes, updated)
  end

  defp child_path(nil, name), do: name
  defp child_path(parent_path, name), do: Path.join(parent_path, name)

  defp upsert(nodes, %TreeNode{} = node) do
    case Enum.split_while(nodes, &(&1.name != node.name or &1.kind != node.kind)) do
      {before, [_existing | after_nodes]} -> before ++ [node | after_nodes]
      {_before, []} -> nodes ++ [node]
    end
  end
end
