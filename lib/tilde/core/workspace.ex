defmodule Tilde.Core.Workspace do
  @moduledoc """
  Renderer-neutral read-only workspace state for a Tilde session.

  The workspace is a projection of repository files plus session file activity.
  Renderers decide how to present the file pane and later previews.
  """

  alias Tilde.Core.Workspace.{File, Section, Tree}

  defstruct root: nil,
            files: [],
            selected_path: nil,
            focused_path: nil,
            filter: "",
            expanded_paths: MapSet.new()

  @type t :: %__MODULE__{
          root: String.t() | nil,
          files: [File.t()],
          selected_path: String.t() | nil,
          focused_path: String.t() | nil,
          filter: String.t(),
          expanded_paths: MapSet.t(String.t())
        }

  @doc "Returns relevant file sections with path-natural trees."
  @spec file_sections(t()) :: [Section.t()]
  def file_sections(%__MODULE__{files: files}) do
    [
      file_section("session", Enum.filter(files, &session_file?/1)),
      file_section("changed", Enum.filter(files, &changed_file?/1))
    ]
    |> Enum.reject(&(&1.files == []))
  end

  defp file_section(title, files) do
    Section.new(title: title, files: files, tree: Tree.from_files(files))
  end

  defp session_file?(%File{session_state: state}), do: state != :untouched

  defp changed_file?(%File{git_status: git_status, session_state: session_state}) do
    git_status != :clean and session_state == :untouched
  end

  @doc "Preserves selected/focused navigation from a previous workspace projection."
  @spec preserve_navigation(t(), t() | term()) :: t()
  def preserve_navigation(%__MODULE__{} = workspace, %__MODULE__{} = previous) do
    %{workspace | selected_path: previous.selected_path, focused_path: previous.focused_path}
  end

  def preserve_navigation(%__MODULE__{} = workspace, _previous), do: workspace

  @doc "Returns visible file paths in section/tree order."
  @spec visible_file_paths(t()) :: [String.t()]
  def visible_file_paths(%__MODULE__{} = workspace) do
    workspace
    |> file_sections()
    |> Enum.flat_map(&tree_file_paths(&1.tree))
  end

  @doc "Moves focused_path to the next/previous visible file, wrapping around."
  @spec focus_file(t(), :previous | :next) :: t()
  def focus_file(%__MODULE__{} = workspace, direction) when direction in [:previous, :next] do
    case next_file_path(visible_file_paths(workspace), workspace.focused_path, direction) do
      nil -> workspace
      path -> %{workspace | focused_path: path}
    end
  end

  defp next_file_path([], _current_path, _direction), do: nil
  defp next_file_path(paths, nil, :previous), do: List.last(paths)
  defp next_file_path([path | _paths], nil, :next), do: path

  defp next_file_path(paths, current_path, direction) do
    current_index = Enum.find_index(paths, &(&1 == current_path)) || default_index(direction)
    next_index = Integer.mod(current_index + step(direction), length(paths))
    Enum.at(paths, next_index)
  end

  defp default_index(:previous), do: 0
  defp default_index(:next), do: -1
  defp step(:previous), do: -1
  defp step(:next), do: 1

  defp tree_file_paths(nodes) do
    Enum.flat_map(nodes, fn
      %{kind: :file, file: %{path: path}} -> [path]
      %{children: children} -> tree_file_paths(children)
    end)
  end

  @doc "Creates a workspace state."
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    files = Keyword.get(opts, :files, [])

    %__MODULE__{
      root: Keyword.get(opts, :root),
      files: files,
      selected_path: Keyword.get(opts, :selected_path),
      focused_path: Keyword.get(opts, :focused_path),
      filter: Keyword.get(opts, :filter, ""),
      expanded_paths: Keyword.get(opts, :expanded_paths, MapSet.new())
    }
  end
end
