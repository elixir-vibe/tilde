defmodule Tilde.Transport.Live.WorkspaceTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.FileSymbol
  alias Tilde.Core.Workspace
  alias Tilde.Core.Workspace.File, as: WorkspaceFile

  test "renders relevant workspace sections and hides clean untouched files" do
    workspace =
      Workspace.new(
        selected_path: "lib/write.ex",
        focused_path: "lib/read.ex",
        files: [
          WorkspaceFile.new(path: "lib/clean.ex"),
          WorkspaceFile.new(path: "lib/read.ex", session_state: :read),
          WorkspaceFile.new(path: "lib/changed.ex", git_status: :modified),
          WorkspaceFile.new(path: "lib/write.ex", session_state: :modified, git_status: :modified)
        ]
      )

    html = render_component(&Tilde.Transport.Live.Workspace.file_pane/1, workspace: workspace)

    assert html =~ ~s|aria-label="workspace context"|
    assert html =~ "workspace"
    assert html =~ "write.ex"
    assert html =~ "session"
    assert html =~ "changed"
    assert html =~ ~s|phx-click="tilde:workspace:open_file"|
    assert html =~ ~s|phx-click="tilde:workspace:view_files"|
    assert html =~ ~s|phx-click="tilde:workspace:view_symbols"|
    assert html =~ ~s|<kbd class="key">f</kbd>|
    assert html =~ ~s|<kbd class="key">s</kbd>|
    assert html =~ ~s|phx-value-path="lib/read.ex"|
    assert html =~ ~s|data-path="lib/read.ex"|
    assert html =~ ~s|data-focused role="listitem"|
    assert html =~ ~s|data-path="lib/changed.ex"|
    assert html =~ ~s|data-path="lib/write.ex"|
    assert file_paths(html) == ["lib/read.ex", "lib/write.ex", "lib/changed.ex"]
    assert html =~ "read in session"
    assert html =~ "git modified"
    assert html =~ ~s|class="file focused read"|
    assert html =~ ~s|class="file selected changed git-modified modified"|
  end

  test "renders relevant files as a path-natural tree" do
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

    html = render_component(&Tilde.Transport.Live.Workspace.file_pane/1, workspace: workspace)

    assert html =~ ~s|class="file directory"|
    assert html =~ ~s|style="--depth: 0"|
    assert html =~ ~s|style="--depth: 1"|
    assert html =~ ~s|style="--depth: 4"|
    assert html =~ "assets"
    assert html =~ "css"
    assert html =~ "tilde"
    assert html =~ "components"

    assert file_labels(html) == [
             "app.css",
             "footer.css",
             "workspace.css",
             "layout.css",
             "app.ts"
           ]

    assert file_paths(html) == [
             "assets/css/app.css",
             "assets/css/tilde/components/footer.css",
             "assets/css/tilde/components/workspace.css",
             "assets/css/tilde/layout.css",
             "assets/js/app.ts"
           ]

    assert html =~ ~s|data-path="assets/css/tilde/components/footer.css"|
    assert html =~ ~s|title="assets/css/tilde/components/footer.css · git modified"|
  end

  test "renders an empty state when no files are relevant" do
    workspace = Workspace.new(files: [WorkspaceFile.new(path: "lib/clean.ex")])

    html = render_component(&Tilde.Transport.Live.Workspace.file_pane/1, workspace: workspace)

    assert html =~ "No active files yet."
    assert file_paths(html) == []
  end

  test "renders shared footer actions when provided" do
    workspace =
      Workspace.new(files: [WorkspaceFile.new(path: "lib/read.ex", session_state: :read)])

    html =
      render_component(&Tilde.Transport.Live.Workspace.file_pane/1,
        workspace: workspace,
        actions: [%{event: "tilde:session:chat", label: "chat", kind: :mobile}]
      )

    assert html =~ ~s|class="footer"|
    assert html =~ ~s|class="action mobile"|
    assert html =~ ~s|phx-click="tilde:session:chat"|
    assert html =~ "chat"
  end

  test "renders current file symbols as a workspace view" do
    workspace =
      Workspace.new(files: [WorkspaceFile.new(path: "lib/example.ex", session_state: :read)])

    symbols = [
      FileSymbol.new(name: "Example", kind: :module, line: 1),
      FileSymbol.new(name: "def run/1", kind: :function, line: 3),
      FileSymbol.new(name: "@type t/0", kind: :type, line: 5),
      FileSymbol.new(name: "@callback call/1", kind: :callback, line: 7)
    ]

    html =
      render_component(&Tilde.Transport.Live.Workspace.file_pane/1,
        workspace: workspace,
        view: :symbols,
        symbols: symbols,
        active_symbol_line: 3
      )

    assert html =~ ~s|aria-label="workspace views"|
    assert html =~ ~s|class="action selected"|
    assert html =~ ~s|<kbd class="key">f</kbd>|
    assert html =~ ~s|<kbd class="key">s</kbd>|
    assert html =~ ~s|phx-click="tilde:buffer:jump_symbol"|
    assert html =~ ~s|phx-value-line="1"|
    assert html =~ ~s|phx-value-line="3"|
    assert html =~ ~s|phx-value-line="5"|
    assert html =~ ~s|phx-value-line="7"|
    assert html =~ ~s|aria-label="modules"|
    assert html =~ ~s|aria-label="functions"|
    assert html =~ ~s|aria-label="types"|
    assert html =~ "Example"
    assert html =~ "def run/1"
    assert html =~ "@type t/0"
    assert html =~ "@callback call/1"
    assert html =~ ~s|class="line" aria-label="line 3">3</span>|
    assert html =~ ~s|class="line" aria-label="line 7">7</span>|
    assert html =~ ~s|class="file symbol function selected"|
    assert html =~ ~s|class="file symbol type"|
    assert html =~ ~s|class="file symbol callback"|
    assert symbol_labels(html) == ["Example", "def run/1", "@type t/0", "@callback call/1"]
  end

  defp file_paths(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".workspace button.file[data-path]")
    |> Enum.map(fn node -> node |> Floki.attribute("data-path") |> List.first() end)
  end

  defp file_labels(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".workspace button.file .path")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end

  defp symbol_labels(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".workspace .symbols button.file .path")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
  end
end
