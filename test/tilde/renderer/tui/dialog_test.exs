defmodule Tilde.Renderer.TUI.DialogTest do
  use TildeTest.Case

  test "renders semantic dialog widgets as terminal boxes" do
    session =
      Tilde.session(id: "dialog-session")
      |> Tilde.Core.Session.put_widget(
        Tilde.dialog("confirm", "Confirm", "Continue with this action?",
          actions: [
            Tilde.action(:ok, "OK", key: "enter"),
            Tilde.action(:cancel, "Cancel", key: "esc")
          ]
        )
      )

    rendered =
      session
      |> Tilde.Renderer.TUI.render_to_string(width: 50, ansi: false, clear?: false)
      |> strip_ansi()

    assert rendered =~ "╭ Confirm"
    assert rendered =~ "│ Continue with this action?"
    assert rendered =~ "enter OK    esc Cancel"
    assert rendered =~ "╰"
  end
end
