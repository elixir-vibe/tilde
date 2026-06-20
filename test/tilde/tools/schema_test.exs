defmodule Tilde.Tools.SchemaTest do
  use TildeTest.Case, async: true

  test "coding tools expose JSONSpec schemas to Jido" do
    names = Tilde.Tools.coding_tools() |> Enum.map(& &1.to_tool().name)
    assert "list" in names

    list_schema = Tilde.Tools.List.to_tool().parameters_schema
    assert list_schema["properties"]["path"]["description"] =~ "directory"

    schema = Tilde.Tools.Edit.to_tool().parameters_schema

    assert schema["properties"]["edits"]["items"]["properties"]["oldText"] == %{
             "type" => "string"
           }

    assert schema["properties"]["edits"]["items"]["properties"]["newText"] == %{
             "type" => "string"
           }
  end
end
