defmodule Tilde.Core.PaletteTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.{FileBuffer, FileSymbol, Palette}
  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.File, as: WorkspaceFile

  test "builds file items from relevant workspace sections" do
    workspace =
      Workspace.new(
        files: [
          WorkspaceFile.new(path: "lib/clean.ex"),
          WorkspaceFile.new(path: "lib/read.ex", session_state: :read),
          WorkspaceFile.new(path: "assets/css/app.css", git_status: :modified)
        ]
      )

    palette = Palette.open_files(workspace)

    assert palette.mode == :files
    assert Enum.map(palette.items, & &1.detail) == ["assets/css/app.css", "lib/read.ex"]
    assert Enum.map(palette.items, & &1.label) == ["app.css", "read.ex"]

    assert Palette.selected_item(palette).action == %{
             type: :open_file,
             path: "assets/css/app.css"
           }
  end

  test "filters by query terms and prefers basename matches" do
    workspace =
      Workspace.new(
        files: [
          WorkspaceFile.new(path: "assets/css/workspace.css", git_status: :modified),
          WorkspaceFile.new(path: "lib/tilde/transport/live/workspace.ex", git_status: :modified),
          WorkspaceFile.new(
            path: "test/tilde/transport/live/workspace_test.exs",
            git_status: :modified
          )
        ]
      )

    palette = Palette.open_files(workspace, "workspace ex")

    assert Enum.map(palette.items, & &1.detail) == [
             "lib/tilde/transport/live/workspace.ex",
             "test/tilde/transport/live/workspace_test.exs"
           ]
  end

  test "builds symbol items from the current open file" do
    open_file =
      FileBuffer.new(
        path: "lib/example.ex",
        symbols: [
          FileSymbol.new(name: "Example", kind: :module, line: 1),
          FileSymbol.new(name: "def run/1", kind: :function, line: 12)
        ]
      )

    palette = Palette.open_symbols(open_file, "run")

    assert palette.mode == :symbols
    assert Enum.map(palette.items, & &1.label) == ["def run/1"]
    assert Palette.selected_item(palette).detail == "function · line 12"

    assert Palette.selected_item(palette).action == %{
             type: :jump_symbol,
             path: "lib/example.ex",
             line: 12
           }
  end

  test "switches between file and symbol modes using the current query" do
    workspace =
      Workspace.new(files: [WorkspaceFile.new(path: "lib/example.ex", git_status: :modified)])

    open_file =
      FileBuffer.new(
        path: "lib/example.ex",
        symbols: [FileSymbol.new(name: "def run/1", kind: :function, line: 12)]
      )

    palette = Palette.open_files(workspace, "run")
    assert palette.items == []

    palette = Palette.switch_mode(palette, :symbols, workspace, open_file)
    assert palette.mode == :symbols
    assert Enum.map(palette.items, & &1.label) == ["def run/1"]
  end

  test "moves selected item with wrapping" do
    palette = Palette.new(items: [item("a"), item("b"), item("c")])

    assert Palette.move(palette, :previous).selected_index == 2
    assert palette |> Palette.move(:next) |> Palette.move(:next) |> Palette.move(:next) == palette
  end

  defp item(path), do: Tilde.Core.Palette.Item.new(id: path, label: path, detail: path)
end
