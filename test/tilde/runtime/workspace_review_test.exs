defmodule Tilde.Runtime.WorkspaceReviewTest do
  use TildeTest.Case, async: false

  alias Tilde.Core.Review
  alias Tilde.Runtime.WorkspaceFiles
  alias Tilde.Runtime.WorkspaceReview
  alias Tilde.Session.ReviewState

  test "builds review comments from git working tree changes" do
    root = tmp_dir()
    File.write!(Path.join(root, "tracked.ex"), "defmodule Tracked do\n  def value, do: 1\nend\n")

    git!(root, ["init"])
    git!(root, ["config", "user.email", "tilde@example.test"])
    git!(root, ["config", "user.name", "Tilde"])
    git!(root, ["add", "."])
    git!(root, ["commit", "-m", "initial"])

    File.write!(Path.join(root, "tracked.ex"), "defmodule Tracked do\n  def value, do: 2\nend\n")
    File.write!(Path.join(root, "new.ex"), "defmodule NewFile do\nend\n")

    workspace = WorkspaceFiles.workspace(Tilde.session(id: "review"), root: root)
    review = WorkspaceReview.review(workspace)

    tracked_comment = review |> Review.file_comments("tracked.ex") |> List.first()
    new_comment = review |> Review.file_comments("new.ex") |> List.first()

    assert review.title == "working tree review"
    assert tracked_comment.line == 2
    assert tracked_comment.severity == :issue
    assert tracked_comment.body =~ "working tree diff"
    assert new_comment.line == 1
    assert new_comment.severity == :warning
  end

  test "applies persisted review statuses from session metadata" do
    root = tmp_dir()
    File.write!(Path.join(root, "tracked.ex"), "defmodule Tracked do\n  def value, do: 1\nend\n")

    git!(root, ["init"])
    git!(root, ["config", "user.email", "tilde@example.test"])
    git!(root, ["config", "user.name", "Tilde"])
    git!(root, ["add", "."])
    git!(root, ["commit", "-m", "initial"])

    File.write!(Path.join(root, "tracked.ex"), "defmodule Tracked do\n  def value, do: 2\nend\n")

    session = Tilde.session(id: "persisted-review")
    workspace = WorkspaceFiles.workspace(session, root: root)
    review = WorkspaceReview.review(workspace, session)
    comment = review |> Review.comments() |> List.first()

    session = ReviewState.put(session, Review.resolve_comment(review, comment.id))
    loaded = WorkspaceReview.review(workspace, session)

    assert %{status: :resolved} = Review.find_comment(loaded, comment.id)
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tilde-review-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp git!(root, args) do
    assert {_output, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
  end
end
