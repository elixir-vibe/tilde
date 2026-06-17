defmodule Tilde.DevTest do
  use TildeTest.Case, async: false

  test "devtools can be enabled from application config" do
    with_application_env(:devtools, true, fn ->
      assert Tilde.Dev.enabled?()
    end)

    with_application_env(:devtools, false, fn ->
      previous = System.get_env("TILDE_DEVTOOLS")
      System.delete_env("TILDE_DEVTOOLS")

      try do
        refute Tilde.Dev.enabled?()
      after
        restore_system_env("TILDE_DEVTOOLS", previous)
      end
    end)
  end

  test "inspector formats the raw session" do
    session =
      Tilde.session(id: "inspect-me") |> Session.append_event(Tilde.input_submitted("hello"))

    raw = Tilde.Dev.Inspector.session(session)

    assert raw =~ "%Tilde.Core.Session{"
    assert raw =~ "id: \"inspect-me\""
    assert raw =~ "events:"
    assert raw =~ "transcript:"
  end
end
