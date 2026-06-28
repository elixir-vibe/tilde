defmodule Tilde.Renderer.TUI.Workspace do
  @moduledoc """
  Projects workspace file sections to terminal text.

  This renderer consumes `Tilde.Core.Workspace.file_sections/1`, so terminal and
  Live rendering share sectioning and path-natural tree construction.
  """

  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.{File, TreeNode}
  alias Tilde.Renderer.TUI.Theme

  @doc "Renders the relevant workspace files as a nested terminal tree."
  @spec render(Workspace.t(), pos_integer(), keyword()) :: String.t()
  def render(%Workspace{} = workspace, _width, opts \\ []) do
    workspace
    |> Workspace.file_sections()
    |> Enum.map(&render_section(&1, opts))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp render_section(%{title: title, files: files, tree: tree}, opts) do
    header = Theme.muted("#{title} #{length(files)}", opts)
    rows = Enum.map(tree, &render_node(&1, 0, opts))

    [header | rows]
    |> List.flatten()
    |> Enum.join("\n")
  end

  defp render_node(%TreeNode{kind: :directory, name: name, children: children}, depth, opts) do
    [directory_line(name, depth, opts) | Enum.map(children, &render_node(&1, depth + 1, opts))]
  end

  defp render_node(%TreeNode{kind: :file, name: name, file: %File{} = file}, depth, opts) do
    file_line(file, name, depth, opts)
  end

  defp directory_line(name, depth, opts) do
    indent(depth) <> Theme.muted(name, opts)
  end

  defp file_line(%File{} = file, name, depth, opts) do
    indent(depth) <> Theme.muted(File.marks(file), opts) <> " " <> name
  end

  defp indent(depth), do: String.duplicate("  ", depth)
end
