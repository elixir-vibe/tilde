defmodule Tilde.Renderer.TUI.WorkbenchTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Palette
  alias Tilde.Core.Review
  alias Tilde.Core.Review.Comment
  alias Tilde.Core.Review.File, as: ReviewFile
  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.File, as: WorkspaceFile
  alias Tilde.Renderer.TUI.Workbench

  test "renders workspace, main session, review, and palette surfaces" do
    workspace =
      Workspace.new(
        files: [WorkspaceFile.new(path: "lib/demo.ex", git_status: :modified)],
        focused_path: "lib/demo.ex"
      )

    review =
      Review.new(
        title: "working tree review",
        files: [
          ReviewFile.new(
            path: "lib/demo.ex",
            comments: [
              Comment.new(
                id: "review-1",
                path: "lib/demo.ex",
                line: 3,
                severity: :issue,
                body: "Check this change."
              )
            ]
          )
        ]
      )

    rendered =
      %{
        session: Tilde.session() |> Session.append_event(Tilde.assistant_done("hello")),
        workspace: workspace,
        workspace_mode: :chat,
        workspace_view: :files,
        open_file: nil,
        review: review,
        active_review_comment_id: nil,
        palette: Palette.open_files(workspace)
      }
      |> Workbench.render(80, 40, ansi: false)
      |> IO.iodata_to_binary()
      |> strip_ansi()

    assert rendered =~ "── workspace ──"
    assert rendered =~ "~ demo.ex"
    assert rendered =~ "── main ──"
    assert rendered =~ "hello"
    assert rendered =~ "── review ──"
    assert rendered =~ "working tree review"
    assert rendered =~ "open file"
  end

  test "uses side-by-side panes on wide terminals" do
    workspace =
      Workspace.new(
        files: [WorkspaceFile.new(path: "lib/demo.ex", git_status: :modified)],
        focused_path: "lib/demo.ex"
      )

    review =
      Review.new(
        title: "working tree review",
        files: [
          ReviewFile.new(
            path: "lib/demo.ex",
            comments: [
              Comment.new(
                id: "review-1",
                path: "lib/demo.ex",
                line: 3,
                severity: :issue,
                body: "Check this change."
              )
            ]
          )
        ]
      )

    rendered =
      %{
        session: Tilde.session() |> Session.append_event(Tilde.assistant_done("hello")),
        workspace: workspace,
        workspace_mode: :chat,
        workspace_view: :files,
        open_file: nil,
        review: review,
        active_review_comment_id: nil,
        palette: Palette.new()
      }
      |> Workbench.render(140, 30, ansi: false)
      |> IO.iodata_to_binary()
      |> strip_ansi()

    assert rendered =~ " workspace "
    assert rendered =~ " main "
    assert rendered =~ " review "
    assert rendered =~ " │ "
    refute rendered =~ "── workspace ──"
  end
end
