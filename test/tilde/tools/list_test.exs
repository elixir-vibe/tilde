defmodule Tilde.Tools.ListTest do
  use TildeTest.Case, async: true

  test "lists directory entries without hidden files by default" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "README.md"), "hello")
    File.mkdir_p!(Path.join(dir, "lib"))
    File.write!(Path.join(dir, ".secret"), "hidden")

    assert {:ok, result} = Tilde.Tools.List.run(%{"path" => dir}, %{})

    text = result.content |> List.first() |> Map.fetch!(:text)
    assert text =~ "README.md"
    assert text =~ "lib/"
    refute text =~ ".secret"
    assert result.total_entries == 2
  end

  test "can include hidden files and limit entries" do
    dir = tmp_dir()
    File.write!(Path.join(dir, ".env"), "x")
    File.write!(Path.join(dir, "a.txt"), "a")
    File.write!(Path.join(dir, "b.txt"), "b")

    assert {:ok, result} =
             Tilde.Tools.List.run(%{"path" => dir, "all" => true, "limit" => 2}, %{})

    text = result.content |> List.first() |> Map.fetch!(:text)
    assert text =~ "(2 of 3 entries)"
    assert result.total_entries == 3
    assert result.selected_entries == 2
  end

  test "rejects regular files" do
    dir = tmp_dir()
    path = Path.join(dir, "file.txt")
    File.write!(path, "hello")

    assert {:error, "not a directory: regular"} = Tilde.Tools.List.run(%{"path" => path}, %{})
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tilde-list-tool-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end
end
