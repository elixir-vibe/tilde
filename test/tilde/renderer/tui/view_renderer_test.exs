defmodule Tilde.Renderer.TUI.ViewRendererTest do
  use TildeTest.Case

  test "choice actions render from shared semantic actions" do
    choice = Tilde.choice("Proceed?", [{"yes", "Yes"}, {"no", "No"}])
    cell = Tilde.choice_block("choice_1", choice) |> Tilde.Viewable.to_view()

    rendered = cell |> Tilde.Renderer.TUI.ViewRenderer.render(60, ansi: false) |> strip_ansi()

    assert rendered =~ "Proceed?"
    assert rendered =~ "[ ] Yes"
    assert rendered =~ "enter Confirm    escape Cancel"
  end
end
