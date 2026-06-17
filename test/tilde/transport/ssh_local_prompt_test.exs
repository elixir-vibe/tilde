defmodule Tilde.Transport.SSH.LocalPromptTest do
  use TildeTest.Case, async: true

  alias Tilde.Transport.SSH.LocalPrompt

  test "edits prompt locally without requiring a session server" do
    state = %{session: Tilde.session()}

    assert {:cont, {:cont, state}} = LocalPrompt.apply_key(state, {:text, "h"})
    assert state.session.input.value == "h"

    assert {:cont, {:cont, state}} = LocalPrompt.apply_key(state, :backspace)
    assert state.session.input.value == ""
  end

  test "preserves non-empty local prompt across shared session updates" do
    incoming = Tilde.session(id: "shared")
    current = Tilde.session(id: "shared") |> Session.append_event(Tilde.input_changed("draft"))

    assert %{input: %{value: "draft"}} = LocalPrompt.preserve(incoming, current)
  end
end
