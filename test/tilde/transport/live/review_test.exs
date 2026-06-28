defmodule Tilde.Transport.Live.ReviewTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Review
  alias Tilde.Core.Review.{Comment, File}

  test "renders right review pane with current file comments and other files" do
    current_comment =
      Comment.new(
        id: "c1",
        path: "lib/current.ex",
        line: 7,
        severity: :issue,
        body: "Fix this branch."
      )

    other_comment =
      Comment.new(
        id: "c2",
        path: "lib/other.ex",
        line: 3,
        severity: :note,
        body: "Consider shared vocabulary."
      )

    review =
      Review.new(
        title: "working tree review",
        files: [
          File.new(path: "lib/current.ex", comments: [current_comment]),
          File.new(path: "lib/other.ex", comments: [other_comment])
        ]
      )

    html =
      render_component(&Tilde.Transport.Live.Review.review_pane/1,
        review: review,
        current_path: "lib/current.ex",
        active_comment_id: "c1"
      )

    assert html =~ ~s|aria-label="review comments"|
    assert html =~ "working tree review"
    assert html =~ "Fix this branch."
    assert html =~ ~s|class="comment issue open selected"|
    assert html =~ ~s|phx-click="tilde:review:jump_comment"|
    assert html =~ ~s|phx-click="tilde:review:resolve_comment"|
    assert html =~ ~s|phx-value-comment-id="c1"|
    assert html =~ "lib/other.ex"
  end

  test "renders reopen action for resolved comments" do
    comment =
      Comment.new(
        id: "c1",
        path: "lib/current.ex",
        line: 7,
        severity: :warning,
        status: :resolved,
        body: "Already fixed."
      )

    review =
      Review.new(
        title: "working tree review",
        files: [File.new(path: "lib/current.ex", comments: [comment])]
      )

    html =
      render_component(&Tilde.Transport.Live.Review.review_pane/1,
        review: review,
        current_path: "lib/current.ex",
        active_comment_id: "c1"
      )

    assert html =~ ~s|class="comment warning resolved selected"|
    assert html =~ "resolved warning line 7"
    assert html =~ ~s|phx-click="tilde:review:reopen_comment"|
    refute html =~ ~s|phx-click="tilde:review:resolve_comment"|
  end
end
