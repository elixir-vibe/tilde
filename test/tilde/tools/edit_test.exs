defmodule Tilde.Tools.EditTest do
  use TildeTest.Case, async: false

  test "edits exact unique replacements and returns semantic diff details" do
    path = tmp_path("edit-example.txt")
    File.write!(path, "one\ntwo\nthree\n")

    assert {:ok, result} =
             Tilde.Tools.Edit.run(
               %{"path" => path, "edits" => [%{"oldText" => "two", "newText" => "TWO"}]},
               %{}
             )

    assert File.read!(path) == "one\nTWO\nthree\n"

    assert %{content: [%{text: "Successfully replaced 1 block(s)" <> _}], details: details} =
             result

    assert details.diff =~ "-2  two"
    assert details.diff =~ "+2  TWO"
    assert details.patch =~ "--- a/"
  end

  test "rejects duplicate oldText" do
    path = tmp_path("edit-duplicate.txt")
    File.write!(path, "same\nsame\n")

    assert {:error, reason} =
             Tilde.Tools.Edit.run(
               %{"path" => path, "edits" => [%{"oldText" => "same", "newText" => "other"}]},
               %{}
             )

    assert reason =~ "Each oldText must be unique"
  end

  defp tmp_path(name),
    do: Path.join(System.tmp_dir!(), "tilde-#{System.unique_integer([:positive])}-#{name}")
end
