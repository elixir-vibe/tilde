defmodule Tilde.Runtime.WorkspaceFilesTest do
  use TildeTest.Case, async: false

  alias Tilde.Runtime.WorkspaceFiles

  test "builds workspace files with git and session state" do
    root = tmp_dir()
    File.write!(Path.join(root, "tracked.ex"), "defmodule Tracked do\nend\n")
    File.write!(Path.join(root, "read.ex"), "defmodule Read do\nend\n")

    git!(root, ["init"])
    git!(root, ["config", "user.email", "tilde@example.test"])
    git!(root, ["config", "user.name", "Tilde"])
    git!(root, ["add", "."])
    git!(root, ["commit", "-m", "initial"])

    File.write!(
      Path.join(root, "tracked.ex"),
      "defmodule Tracked do\n  def changed, do: true\nend\n"
    )

    session =
      Tilde.session(id: "workspace")
      |> Session.append_event(
        Tilde.tool_started("read", %{path: "read.ex"}, tool_call_id: "read_1")
      )
      |> Session.append_event(
        Tilde.tool_started("write", %{path: "tracked.ex"}, tool_call_id: "write_1")
      )

    workspace = WorkspaceFiles.workspace(session, root: root)

    tracked = Enum.find(workspace.files, &(&1.path == "tracked.ex"))
    read = Enum.find(workspace.files, &(&1.path == "read.ex"))

    assert tracked.git_status == :modified
    assert tracked.session_state == :modified
    assert read.git_status == :clean
    assert read.session_state == :read
  end

  test "opens bounded files from the workspace" do
    root = tmp_dir()
    File.write!(Path.join(root, "sample.ex"), "defmodule Sample do\nend\n")

    git!(root, ["init"])
    git!(root, ["add", "."])

    workspace = WorkspaceFiles.workspace(Tilde.session(id: "open-file"), root: root)
    file = WorkspaceFiles.open_file(workspace, "sample.ex")

    assert file.path == "sample.ex"
    assert file.content =~ "defmodule Sample"
    assert file.error == nil
    assert Enum.map(file.symbols, & &1.name) == ["Sample"]

    outside = WorkspaceFiles.open_file(workspace, "../secret.ex")
    assert outside.error == "file is not in workspace"
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tilde-workspace-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  defp git!(root, args) do
    assert {_output, 0} = System.cmd("git", args, cd: root, stderr_to_stdout: true)
  end
end
