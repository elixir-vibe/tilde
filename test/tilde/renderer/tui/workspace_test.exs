defmodule Tilde.Renderer.TUI.WorkspaceTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.File, as: WorkspaceFile
  alias Tilde.Renderer.TUI.Workspace, as: WorkspaceRenderer

  test "renders relevant files as a path-natural terminal tree" do
    workspace =
      Workspace.new(
        files: [
          WorkspaceFile.new(path: "assets/css/app.css", git_status: :modified),
          WorkspaceFile.new(
            path: "assets/css/tilde/components/footer.css",
            git_status: :modified
          ),
          WorkspaceFile.new(
            path: "assets/css/tilde/components/workspace.css",
            git_status: :untracked
          ),
          WorkspaceFile.new(path: "assets/css/tilde/layout.css", git_status: :modified),
          WorkspaceFile.new(path: "assets/js/app.ts", git_status: :modified)
        ]
      )

    assert WorkspaceRenderer.render(workspace, 80, ansi: false) ==
             """
             changed 5
             assets
               css
                 ~ app.css
                 tilde
                   components
                     ~ footer.css
                     ? workspace.css
                   ~ layout.css
               js
                 ~ app.ts
             """
             |> String.trim_trailing()
  end
end
