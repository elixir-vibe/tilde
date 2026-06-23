defmodule Tilde.Transport.Live.DialogTest do
  use TildeTest.Case

  test "renders shared dialog chrome" do
    html =
      render_component(&Tilde.Transport.Live.Dialog.dialog/1,
        id: "confirm",
        title: "Confirm",
        body: "Continue?",
        actions: [Tilde.action(:confirm, "Confirm", key: "enter")]
      )

    assert html =~ ~s|id="confirm"|
    assert html =~ ~s|class="dialog"|
    assert html =~ ~s|role="dialog"|
    assert html =~ ~s|aria-modal|
    assert html =~ "Confirm"
    assert html =~ "Continue?"
    assert html =~ ~s|class="actions"|
    assert html =~ ~s|class="shortcut |
    assert html =~ ~s|<kbd class="key">enter</kbd>|
  end

  test "renders dialog widgets in the console" do
    session =
      Tilde.session(id: "dialog-session")
      |> Tilde.Core.Session.put_widget(
        Tilde.dialog("confirm", "Confirm", "Continue?",
          actions: [Tilde.action(:ok, "OK", key: "enter")]
        )
      )

    html = render_component(&Tilde.Transport.Live.Console.console/1, session: session)

    assert html =~ ~s|data-placement="overlay"|
    assert html =~ ~s|id="confirm"|
    assert html =~ ~s|class="dialog"|
    refute html =~ ~s|<aside id="confirm"|
    assert html =~ "Continue?"
    assert html =~ "OK"
  end
end
