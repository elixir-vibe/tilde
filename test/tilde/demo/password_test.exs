defmodule Tilde.Demo.PasswordTest do
  use TildeTest.Case

  test "generated once when not configured" do
    previous = Application.get_env(:tilde, :demo_password)
    Application.delete_env(:tilde, :demo_password)

    first = Tilde.Demo.Password.get()
    second = Tilde.Demo.Password.get()

    assert first == second
    assert byte_size(first) >= 32
    assert Tilde.Demo.Password.valid?(first)

    restore_application_env(:demo_password, previous)
  end
end
