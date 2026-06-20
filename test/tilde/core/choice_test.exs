defmodule Tilde.Core.ChoiceTest do
  use TildeTest.Case

  test "blocks model pi-like selection without renderer coupling" do
    choice =
      "Proceed?"
      |> Tilde.choice([{"yes", "Yes"}, {"no", "No"}], selected: ["yes"])
      |> Choice.select("no")

    block = Tilde.choice_block("choice_1", choice)

    assert block.kind == :choice
    assert block.choice.selected == ["no"]
    assert Enum.map(block.actions, & &1.id) == [:confirm, :cancel]
  end
end
