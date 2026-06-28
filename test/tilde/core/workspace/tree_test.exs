defmodule Tilde.Core.Workspace.TreeTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Workspace.File, as: WorkspaceFile
  alias Tilde.Core.Workspace.Tree

  test "builds a path-natural nested tree from relevant files" do
    files = [
      WorkspaceFile.new(path: "assets/css/tilde/components/footer.css", git_status: :modified),
      WorkspaceFile.new(path: "assets/js/app.ts", git_status: :modified),
      WorkspaceFile.new(path: "assets/css/app.css", git_status: :modified),
      WorkspaceFile.new(path: "assets/css/tilde/layout.css", git_status: :modified)
    ]

    [assets] = Tree.from_files(files)
    assert assets.name == "assets"
    assert Enum.map(assets.children, & &1.name) == ["css", "js"]

    [css, js] = assets.children
    assert Enum.map(css.children, & &1.name) == ["app.css", "tilde"]
    assert Enum.map(js.children, & &1.name) == ["app.ts"]

    [app_css, tilde] = css.children
    assert app_css.kind == :file
    assert app_css.file.path == "assets/css/app.css"

    assert Enum.map(tilde.children, & &1.name) == ["components", "layout.css"]
    [components, layout] = tilde.children
    assert Enum.map(components.children, & &1.name) == ["footer.css"]
    assert layout.file.path == "assets/css/tilde/layout.css"
  end

  test "keeps full workspace file metadata on leaf nodes" do
    [node] =
      Tree.from_files([
        WorkspaceFile.new(
          path: "lib/example.ex",
          session_state: :read,
          git_status: :modified,
          previewable?: false
        )
      ])

    assert node.kind == :directory
    [leaf] = node.children
    assert leaf.name == "example.ex"
    assert leaf.file.session_state == :read
    assert leaf.file.git_status == :modified
    refute leaf.file.previewable?
  end
end
