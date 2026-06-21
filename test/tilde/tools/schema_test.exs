defmodule Tilde.Tools.SchemaTest do
  use TildeTest.Case, async: true

  test "coding tools expose JSONSpec schemas to Jido" do
    names = Tilde.Tools.coding_tools() |> Enum.map(& &1.to_tool().name)
    refute "list" in names

    schema = Tilde.Tools.Edit.to_tool().parameters_schema

    assert schema["properties"]["edits"]["items"]["properties"]["oldText"] == %{
             "type" => "string"
           }

    assert schema["properties"]["edits"]["items"]["properties"]["newText"] == %{
             "type" => "string"
           }
  end
end
