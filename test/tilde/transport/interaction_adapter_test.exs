defmodule Tilde.Transport.InteractionAdapterTest do
  use TildeTest.Case, async: true

  alias Tilde.Core.Interaction
  alias Tilde.Index
  alias Tilde.Transport.Live.Interaction, as: LiveInteraction
  alias Tilde.Transport.SSH.Interaction, as: SSHInteraction

  test "Live index events translate to shared interactions" do
    index = Index.new()

    assert %Interaction{type: :new_shortcut} =
             LiveInteraction.index("tilde:input_changed", %{"input" => "n"}, index)

    assert %Interaction{type: :suggest_submit} =
             LiveInteraction.index("tilde:index_keydown", %{"key" => "Enter"}, index)
  end

  test "Live session events translate to shared interactions" do
    assert %Interaction{type: :toggle_expand, payload: %{id: "tool_1"}} =
             LiveInteraction.session("tilde:toggle_expand", %{"id" => "tool_1"})

    assert %Interaction{type: :toggle_expand, payload: %{}} =
             LiveInteraction.session("tilde:toggle_expand", %{})

    assert %Interaction{type: :select_choice, payload: %{block_id: "choice", option_id: "yes"}} =
             LiveInteraction.session("tilde:select_choice", %{
               "block-id" => "choice",
               "option-id" => "yes"
             })

    assert %Interaction{type: :complete_input, payload: %{insert: "/new "}} =
             LiveInteraction.session("tilde:complete_input", %{"insert" => "/new "})

    assert %Interaction{type: :dialog_action, payload: %{widget_id: "dialog", action_id: "ok"}} =
             LiveInteraction.session("tilde:dialog_action", %{
               "widget-id" => "dialog",
               "action-id" => "ok"
             })
  end

  test "SSH index keys translate to shared interactions" do
    index = Index.new()

    assert %Interaction{type: :new_shortcut} = SSHInteraction.index(index, {:text, "n"})
    assert %Interaction{type: :suggest_submit} = SSHInteraction.index(index, :enter)
    assert :halt = SSHInteraction.index(index, :interrupt)
  end
end
