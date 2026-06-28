defmodule Tilde.Transport.Live.WorkspaceFileTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.{FileBuffer, FileSymbol}

  test "renders opened file as the main workspace surface" do
    file =
      FileBuffer.new(
        path: "lib/example.ex",
        content: "defmodule Example do\nend\n",
        symbols: [FileSymbol.new(name: "Example", kind: :module, line: 1)]
      )

    html =
      render_component(&Tilde.Transport.Live.WorkspaceFile.file_surface/1,
        file: file,
        scroll_line: 1,
        actions: [%{event: "tilde:workspace:show", label: "files", kind: :mobile}]
      )

    assert html =~ ~s|aria-label="opened workspace file"|
    assert html =~ ~s|phx-hook="TildeWorkspaceFile"|
    assert html =~ ~s|data-scroll-line="1"|
    assert html =~ "defmodule"
    assert html =~ ~s|class="l-line has-symbol"|
    assert html =~ "module: Example"
    assert html =~ ~s|phx-click="tilde:workspace:show"|
    assert html =~ ~s|phx-click="tilde:session:chat"|
    assert html =~ ~s|class="action mobile"|
    assert html =~ "lines"
    assert html =~ "bytes"
  end

  test "renders file errors" do
    file = FileBuffer.new(path: "missing.ex", error: "file is not in workspace")

    html = render_component(&Tilde.Transport.Live.WorkspaceFile.file_surface/1, file: file)

    assert html =~ "file is not in workspace"
  end
end
