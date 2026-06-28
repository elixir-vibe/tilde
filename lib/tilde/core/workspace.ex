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
