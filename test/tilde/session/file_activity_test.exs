defmodule Tilde.Session.FileActivityTest do
  use TildeTest.Case, async: true

  alias Tilde.Session.FileActivity

  test "derives read and modified files from tool start events" do
    session =
      Tilde.session(id: "activity")
      |> Session.append_event(
        Tilde.tool_started("read", %{path: "lib/a.ex"}, tool_call_id: "read_1")
      )
      |> Session.append_event(
        Tilde.tool_started("edit", %{path: "lib/b.ex"}, tool_call_id: "edit_1")
      )
      |> Session.append_event(
        Tilde.tool_started("write", %{path: "lib/a.ex"}, tool_call_id: "write_1")
      )

    assert FileActivity.from_session(session) == %{
             "lib/a.ex" => :modified,
             "lib/b.ex" => :modified
           }
  end
end
