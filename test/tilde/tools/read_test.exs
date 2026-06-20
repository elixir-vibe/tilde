defmodule Tilde.Tools.ReadTest do
  use TildeTest.Case, async: false

  test "reads text with offset and limit in Pi-compatible result shape" do
    path = tmp_path("read-example.txt")
    File.write!(path, "one\ntwo\nthree\nfour")

    assert {:ok, result} =
             Tilde.Tools.Read.run(%{"path" => path, "offset" => 2, "limit" => 2}, %{})

    assert %{content: [%{type: "text", text: text}], details: %{truncation: nil}} = result
    assert text =~ "two\nthree"
    assert text =~ "[1 more lines in file. Use offset=4 to continue.]"
  end

  defp tmp_path(name),
    do: Path.join(System.tmp_dir!(), "tilde-#{System.unique_integer([:positive])}-#{name}")
end
