defmodule Tilde.Runtime.WorkspaceFiles do
  @moduledoc """
  Runtime boundary for read-only repository file listings used by Tilde workspaces.
  """

  alias Tilde.Core.FileBuffer
  alias Tilde.Core.Session
  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.File, as: WorkspaceFile
  alias Tilde.Runtime.CodeIntelligence
  alias Tilde.Session.FileActivity

  @max_preview_bytes 64 * 1024
  @max_open_bytes 128 * 1024

  @languages %{
    ".ex" => :elixir,
    ".exs" => :elixir,
    ".heex" => :heex,
    ".js" => :javascript,
    ".jsx" => :javascript,
    ".ts" => :typescript,
    ".tsx" => :typescript,
    ".css" => :css,
    ".json" => :json,
    ".md" => :markdown
  }

  @doc "Builds a workspace projection for a session and project root."
  @spec workspace(Session.t(), keyword()) :: Workspace.t()
  def workspace(%Session{} = session, opts \\ []) do
    root = opts |> Keyword.get(:root, File.cwd!()) |> Path.expand()
    file_activity = FileActivity.from_session(session)
    git_statuses = git_statuses(root)

    files =
      root
      |> list_paths()
      |> Enum.map(&file(root, &1, git_statuses, file_activity))

    Workspace.new(root: root, files: files)
  end

  @doc "Opens a bounded read-only file from a workspace."
  @spec open_file(Workspace.t(), String.t()) :: FileBuffer.t()
  def open_file(%Workspace{root: root, files: files}, path)
      when is_binary(root) and is_binary(path) do
    with %WorkspaceFile{} <- Enum.find(files, &(&1.path == path)),
         {:ok, absolute} <- safe_path(root, path),
         {:ok, stat} <- File.stat(absolute),
         :regular <- stat.type,
         {:ok, content} <- File.read(absolute) do
      truncated? = byte_size(content) > @max_open_bytes
      content = if truncated?, do: binary_part(content, 0, @max_open_bytes), else: content

      symbols = CodeIntelligence.document_symbols(content, path)

      FileBuffer.new(
        path: path,
        content: content,
        size: stat.size,
        truncated?: truncated?,
        symbols: symbols
      )
    else
      nil -> FileBuffer.new(path: path, error: "file is not in workspace")
      {:error, reason} -> FileBuffer.new(path: path, error: inspect(reason))
      type when is_atom(type) -> FileBuffer.new(path: path, error: "not a regular file")
    end
  end

  def open_file(%Workspace{}, path),
    do: FileBuffer.new(path: path, error: "workspace root unavailable")

  defp safe_path(root, path) do
    root = Path.expand(root)
    absolute = Path.expand(Path.join(root, path))

    if String.starts_with?(absolute, root <> "/") or absolute == root do
      {:ok, absolute}
    else
      {:error, :outside_workspace}
    end
  end

  defp list_paths(root) do
    case System.cmd("git", ["ls-files", "-co", "--exclude-standard"],
           cd: root,
           stderr_to_stdout: true
         ) do
      {output, 0} -> output |> String.split("\n", trim: true) |> Enum.sort()
      _other -> []
    end
  end

  defp git_statuses(root) do
    case System.cmd("git", ["status", "--porcelain=v1"], cd: root, stderr_to_stdout: true) do
      {output, 0} -> parse_git_status(output)
      _other -> %{}
    end
  end

  defp parse_git_status(output) do
    output
    |> String.split("\n", trim: true)
    |> Map.new(&status_entry/1)
  end

  defp status_entry(<<?R, _y, ?\s, rest::binary>>) do
    path =
      case String.split(rest, " -> ", parts: 2) do
        [_from, to] -> to
        [from] -> from
      end

    {path, :renamed}
  end

  defp status_entry(<<??, ??, ?\s, path::binary>>), do: {path, :untracked}
  defp status_entry(<<?D, _y, ?\s, path::binary>>), do: {path, :deleted}
  defp status_entry(<<_x, ?D, ?\s, path::binary>>), do: {path, :deleted}
  defp status_entry(<<?A, _y, ?\s, path::binary>>), do: {path, :added}
  defp status_entry(<<?U, _y, ?\s, path::binary>>), do: {path, :conflicted}
  defp status_entry(<<_x, ?U, ?\s, path::binary>>), do: {path, :conflicted}
  defp status_entry(<<_x, _y, ?\s, path::binary>>), do: {path, :modified}

  defp file(root, path, git_statuses, file_activity) do
    absolute = Path.join(root, path)
    stat = File.stat(absolute)

    WorkspaceFile.new(
      path: path,
      kind: kind(stat),
      language: language(path),
      size: size(stat),
      git_status: Map.get(git_statuses, path, :clean),
      session_state: session_state(file_activity, path),
      previewable?: previewable?(stat)
    )
  end

  defp kind({:ok, %{type: :directory}}), do: :directory
  defp kind(_stat), do: :file

  defp size({:ok, %{size: size}}), do: size
  defp size(_stat), do: nil

  defp language(path), do: Map.get(@languages, Path.extname(path))

  defp previewable?({:ok, %{type: :regular, size: size}}), do: size <= @max_preview_bytes
  defp previewable?(_stat), do: false

  defp session_state(file_activity, path) do
    Map.get(file_activity, path) || Map.get(file_activity, Path.expand(path), :untouched)
  end
end
