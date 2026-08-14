defmodule Tilde.WorkbenchTest do
  use TildeTest.Case

  alias Tilde.Core.{Review, Session, Workspace}
  alias Tilde.Workbench

  test "palette, workspace, and file navigation reduce through shared state" do
    workbench = workbench()
    [path | _rest] = Workspace.visible_file_paths(workbench.workspace)

    {workbench, []} = Workbench.apply_action(workbench, {:shortcut, "ctrl+p"})
    assert workbench.palette.open?

    index = Enum.find_index(workbench.palette.items, &(&1.action.path == path))
    {workbench, []} = Workbench.apply_action(workbench, {:select_palette, index})
    {workbench, []} = Workbench.apply_action(workbench, :accept_palette)

    assert workbench.workspace_mode == :file
    assert workbench.workspace.selected_path == path
    assert workbench.open_file.path == path
    refute workbench.palette.open?

    {workbench, []} = Workbench.apply_action(workbench, {:shortcut, "f"})
    assert workbench.workspace_mode == :workspace
    assert workbench.workspace_view == :files

    {workbench, []} = Workbench.apply_action(workbench, {:shortcut, "escape"})
    assert workbench.workspace_mode == :chat
    assert workbench.open_file == nil
  end

  test "review navigation returns a persistence effect without owning storage" do
    workbench = workbench()
    [first, second | _rest] = Review.comments(workbench.review)

    {workbench, []} = Workbench.apply_action(workbench, :focus_review)
    assert workbench.active_review_comment_id == first.id
    assert workbench.open_file.path == first.path

    {workbench, []} = Workbench.apply_action(workbench, {:focus_review, :next})
    assert workbench.active_review_comment_id == second.id
    assert workbench.open_file.path == second.path

    {workbench, [{:persist_review, review}]} =
      Workbench.apply_action(workbench, :toggle_review_comment)

    assert Review.find_comment(review, second.id).status == :resolved
    assert workbench.review == review
  end

  test "refresh preserves workbench navigation while updating semantic session state" do
    workbench = workbench()
    [path | _rest] = Workspace.visible_file_paths(workbench.workspace)
    {workbench, []} = Workbench.apply_action(workbench, {:open_file, path})

    session = Session.append_event(workbench.session, Tilde.assistant_done("updated"))
    refreshed = Workbench.refresh(workbench, session)

    assert refreshed.session == session
    assert refreshed.workspace.selected_path == path
    assert refreshed.open_file.path == path
  end

  test "adapter maps round-trip only shared workbench fields" do
    workbench = workbench()
    adapter_state = Map.merge(%{transport: :ssh, width: 100}, Workbench.to_map(workbench))

    assert Workbench.from_map(adapter_state) == workbench
    refute Map.has_key?(Workbench.to_map(workbench), :transport)
  end

  defp workbench do
    session =
      Tilde.session(id: "workbench-test")
      |> Session.append_event(
        Tilde.tool_started("edit", %{path: "lib/tilde/workbench.ex"}, tool_call_id: "edit-1")
      )
      |> Session.append_event(
        Tilde.tool_started("edit", %{path: "lib/tilde/demo/live.ex"}, tool_call_id: "edit-2")
      )

    Workbench.new(session)
  end
end
