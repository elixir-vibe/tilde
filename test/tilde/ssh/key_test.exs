defmodule Tilde.SSHKeyTest do
  use TildeTest.Case

  test "ssh keys facade uses configured provider" do
    with_application_env(:ssh_key_provider, TildeTest.KeyProvider, fn ->
      assert Tilde.Transport.SSH.Keys.provider() == TildeTest.KeyProvider
      assert Tilde.Transport.SSH.Keys.ensure_system_dir("/tmp/fake") == {:ok, "/tmp/fake"}
    end)
  end

  test "ssh key generation uses Erlang public_key PEM host keys" do
    dir = Path.join(System.tmp_dir!(), "tilde-ssh-test-#{System.unique_integer([:positive])}")

    assert {:ok, ^dir} = Tilde.Transport.SSH.Keys.ensure_system_dir(dir)
    key_path = Path.join(dir, "ssh_host_rsa_key")
    assert File.exists?(key_path)

    assert [{:RSAPrivateKey, _key, :not_encrypted}] =
             key_path |> File.read!() |> :public_key.pem_decode()

    File.rm_rf!(dir)
  end
end
