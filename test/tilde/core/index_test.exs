defmodule Tilde.Core.IndexTest do
  use TildeTest.Case

  alias Tilde.Core.{Index, Interaction}

  test "index footer uses shared clickable command specs" do
    footer =
      Index.new()
      |> Tilde.Index.View.widgets()
      |> Enum.flat_map(& &1.children)
      |> Enum.find(&(&1.kind == :footer))

    assert Enum.map(footer.content.commands, & &1.label) == ["/help", "/showcase", "/new"]
    assert Enum.map(footer.content.commands, & &1.insert) == ["/help", "/showcase", "/new "]
    assert footer.content.right == ""
  end

  test "empty index has no session suggestions" do
    assert {:ok, _pid} = Tilde.Session.Registry.ensure_started()

    index = Index.new()

    assert index.session_suggest == nil
    assert index.command_suggest == nil
  end

  test "index lists real registered sessions" do
    id = "index-#{System.unique_integer([:positive])}"
    assert {:ok, _registry} = Tilde.Session.Registry.ensure_started()
    name = Tilde.Session.Registry.via(id)

    session =
      Tilde.session(id: id)
      |> Session.append_event(Tilde.input_submitted("first prompt"))
      |> Session.append_event(Tilde.assistant_done("last answer"))

    assert {:ok, pid} = Tilde.Session.Server.ensure_started(name, session: session)

    index = Index.new()

    assert %Tilde.Core.Suggest{id: "session-index", items: items} = index.session_suggest
    assert Enum.any?(items, &(&1.label == id and &1.description =~ "first prompt"))
    assert Index.selected_session_id(index) in Enum.map(items, & &1.label)

    GenServer.stop(pid)
  end

  test "command suggestions override session suggestions" do
    index = Index.new() |> Index.input_changed("/")

    assert %Tilde.Core.Suggest{id: "command-suggestions"} = Index.command_suggestions(index)
    assert Index.command_suggestions(index).title == "commands"
  end

  test "index keyboard behavior selects sessions and command completions" do
    id = "open-#{System.unique_integer([:positive])}"
    assert {:ok, _registry} = Tilde.Session.Registry.ensure_started()
    name = Tilde.Session.Registry.via(id)
    assert {:ok, pid} = Tilde.Session.Server.ensure_started(name, session: Tilde.session(id: id))

    index = Index.new()
    assert Index.selected_session_id(index) == id

    command_index = Index.input_changed(index, "/n")
    assert {:ok, completed} = Index.accept_suggestion(command_index)
    assert completed.input.value == "/new "

    assert Index.new_shortcut(index).input.value == "/new "

    GenServer.stop(pid)
  end

  test "index applies transport-neutral interactions" do
    index = Index.new()

    result = Index.apply_interaction(index, Interaction.input_changed("/n"))

    assert_interaction_cont(result)
    refute_outcome(result, :complete_input)

    result = Index.apply_interaction(elem(result, 1), Interaction.new(:suggest_submit))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:complete_input, input: "/new ")
    |> assert_interaction_input("/new ")

    result = Index.apply_interaction(elem(result, 1), Interaction.submit("/new interaction-demo"))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:open_session, id: "interaction-demo", submit: "/new interaction-demo")
  end

  test "index submits non-navigation actions by creating a real session" do
    result = Index.apply_interaction(Index.new(), Interaction.submit("hello from index"))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:open_session, submit: "hello from index")

    result = Index.apply_interaction(Index.new(), Interaction.submit("/help"))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:open_session, submit: "/help")
  end

  test "index enter submits typed input even when session suggestions exist" do
    id = "existing-#{System.unique_integer([:positive])}"
    assert {:ok, _registry} = Tilde.Session.Registry.ensure_started()
    name = Tilde.Session.Registry.via(id)
    assert {:ok, pid} = Tilde.Session.Server.ensure_started(name, session: Tilde.session(id: id))

    index = Index.new() |> Index.input_changed("hi")
    result = Index.apply_interaction(index, Interaction.new(:suggest_submit))

    result
    |> assert_interaction_cont()
    |> assert_outcome(:open_session, submit: "hi")

    GenServer.stop(pid)
  end
end
