defmodule Tilde.Core.ReviewTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Review
  alias Tilde.Core.Review.{Comment, File}

  test "tracks comments across reviewed files" do
    comment =
      Comment.new(
        id: "c1",
        path: "lib/example.ex",
        line: 12,
        severity: :issue,
        body: "Check this."
      )

    review = Review.new(files: [File.new(path: "lib/example.ex", comments: [comment])])

    assert Review.comments(review) == [comment]
    assert Review.open_comment_count(review) == 1
    assert Review.find_comment(review, "c1") == comment
    assert Review.file_comments(review, "lib/example.ex") == [comment]
    assert Review.file_comments(review, "lib/other.ex") == []
  end

  test "resolves and reopens comments" do
    comment =
      Comment.new(
        id: "c1",
        path: "lib/example.ex",
        line: 12,
        severity: :issue,
        body: "Check this."
      )

    review = Review.new(files: [File.new(path: "lib/example.ex", comments: [comment])])

    resolved = Review.resolve_comment(review, "c1")

    assert Review.open_comment_count(resolved) == 0
    assert %Comment{status: :resolved} = Review.find_comment(resolved, "c1")

    reopened = Review.reopen_comment(resolved, "c1")

    assert Review.open_comment_count(reopened) == 1
    assert %Comment{status: :open} = Review.find_comment(reopened, "c1")
  end

  test "navigates adjacent comments in file order" do
    first = Comment.new(id: "c1", path: "lib/one.ex", line: 1, body: "First")
    second = Comment.new(id: "c2", path: "lib/one.ex", line: 4, body: "Second")
    third = Comment.new(id: "c3", path: "lib/two.ex", line: 2, body: "Third")

    review =
      Review.new(
        files: [
          File.new(path: "lib/one.ex", comments: [first, second]),
          File.new(path: "lib/two.ex", comments: [third])
        ]
      )

    assert Review.adjacent_comment_id(review, nil, :next) == "c1"
    assert Review.adjacent_comment_id(review, "c1", :next) == "c2"
    assert Review.adjacent_comment_id(review, "c3", :next) == "c1"
    assert Review.adjacent_comment_id(review, "c1", :previous) == "c3"
    assert Review.adjacent_comment_id(review, "c3", :previous) == "c2"
  end

  test "dumps and applies metadata-safe comment statuses" do
    comment =
      Comment.new(
        id: "c1",
        path: "lib/example.ex",
        line: 12,
        severity: :issue,
        body: "Check this."
      )

    review = Review.new(files: [File.new(path: "lib/example.ex", comments: [comment])])
    resolved = Review.resolve_comment(review, "c1")

    assert Review.dump_statuses(resolved) == %{"c1" => "resolved"}

    assert %Comment{status: :resolved} =
             Review.apply_statuses(review, %{"c1" => "resolved"}) |> Review.find_comment("c1")

    assert %Comment{status: :open} =
             Review.apply_statuses(resolved, %{"c1" => "open"}) |> Review.find_comment("c1")
  end
end
