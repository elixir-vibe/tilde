defmodule Tilde.Runtime.WorkspaceReview do
  @moduledoc """
  Builds review state from the current workspace and Git working tree.

  This module stays at the runtime boundary because it shells out to Git and
  reads the current repository state. The resulting `%Tilde.Core.Review{}` is
  renderer-neutral and can be shared by LiveView and SSH/TUI surfaces.
  """

  alias Tilde.Core.Review
  alias Tilde.Core.Review.Comment
  alias Tilde.Core.Review.File, as: ReviewFile
  alias Tilde.Core.Session
  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.File, as: WorkspaceFile
  alias Tilde.Session.ReviewState

  @doc "Builds a review for changed workspace files, applying persisted statuses from the session."
  @spec review(Workspace.t(), Session.t() | nil) :: Review.t()
  def review(%Workspace{} = workspace, %Session{} = session) do
    workspace
    |> review()
    |> ReviewState.load(session)
  end

  def review(%Workspace{} = workspace, _session), do: review(workspace)

  @doc "Builds a review for changed workspace files."
  @spec review(Workspace.t()) :: Review.t()
  def review(%Workspace{} = workspace) do
    files =
      workspace.files
      |> Enum.filter(&reviewable?/1)
      |> Enum.map(&review_file(workspace.root, &1))
      |> Enum.reject(&(&1.comments == []))

    Review.new(id: "working-tree", title: "working tree review", files: files)
  end

  defp reviewable?(%WorkspaceFile{kind: :file, git_status: git_status, session_state: state}) do
    git_status != :clean or state == :modified
  end

  defp reviewable?(%WorkspaceFile{}), do: false

  defp review_file(root, %WorkspaceFile{} = file) do
    ReviewFile.new(
      path: file.path,
      status: review_file_status(file),
      comments: comments(root, file)
    )
  end

  defp review_file_status(%WorkspaceFile{git_status: :clean}), do: :reviewed
  defp review_file_status(%WorkspaceFile{git_status: :deleted}), do: :needs_changes
  defp review_file_status(%WorkspaceFile{git_status: :conflicted}), do: :needs_changes
  defp review_file_status(%WorkspaceFile{}), do: :pending

  defp comments(_root, %WorkspaceFile{git_status: :deleted} = file) do
    [
      comment(
        file,
        1,
        :warning,
        "File is deleted; review callers and references before removing it."
      )
    ]
  end

  defp comments(root, %WorkspaceFile{git_status: status} = file)
       when status in [:added, :untracked] do
    line = first_changed_line(root, file.path) || 1

    [
      comment(
        file,
        line,
        :warning,
        "New file is not tracked yet; review its public surface and tests before shipping."
      )
    ]
  end

  defp comments(root, %WorkspaceFile{} = file) do
    line = first_changed_line(root, file.path) || 1
    [comment(file, line, severity(file), body(file))]
  end

  defp comment(%WorkspaceFile{path: path}, line, severity, body) do
    Comment.new(
      id: comment_id(path, line),
      path: path,
      line: max(line, 1),
      severity: severity,
      body: body
    )
  end

  defp severity(%WorkspaceFile{git_status: :conflicted}), do: :issue
  defp severity(%WorkspaceFile{git_status: :modified}), do: :issue
  defp severity(%WorkspaceFile{}), do: :note

  defp body(%WorkspaceFile{git_status: :conflicted}) do
    "Conflict markers or unresolved merge state detected; resolve before continuing."
  end

  defp body(%WorkspaceFile{git_status: :modified}) do
    "Review the changed lines from the working tree diff before shipping."
  end

  defp body(%WorkspaceFile{}) do
    "Review this changed file before shipping."
  end

  defp comment_id(path, line) do
    digest = :crypto.hash(:sha256, "#{path}:#{line}") |> Base.encode16(case: :lower)
    "review-" <> binary_part(digest, 0, 12)
  end

  defp first_changed_line(root, path) when is_binary(root) and is_binary(path) do
    root
    |> diff(path)
    |> parse_first_added_line()
  end

  defp first_changed_line(_root, _path), do: nil

  defp diff(root, path) do
    unstaged = git_diff(root, ["diff", "--unified=0", "--", path])
    staged = git_diff(root, ["diff", "--cached", "--unified=0", "--", path])

    [unstaged, staged]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  defp git_diff(root, args) do
    case System.cmd("git", args, cd: root, stderr_to_stdout: true) do
      {output, 0} -> output
      _other -> ""
    end
  end

  defp parse_first_added_line(diff) do
    diff
    |> String.split("\n")
    |> Enum.find_value(&parse_hunk_line/1)
  end

  defp parse_hunk_line("@@ " <> rest) do
    with [range | _tail] <- rest |> String.split(" ") |> Enum.drop(1),
         "+" <> plus_range <- range,
         [start | _count] <- String.split(plus_range, ",", parts: 2),
         {line, ""} <- Integer.parse(start) do
      max(line, 1)
    else
      _other -> nil
    end
  end

  defp parse_hunk_line(_line), do: nil
end
