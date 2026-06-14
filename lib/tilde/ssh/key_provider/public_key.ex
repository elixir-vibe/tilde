defmodule Tilde.SSH.KeyProvider.PublicKey do
  @moduledoc """
  SSH host key provider backed by Erlang/OTP `:public_key`.

  The generated key is a PEM encoded RSA private key suitable for Erlang's SSH
  daemon `system_dir`. No external `ssh-keygen` command is used.
  """

  @behaviour Tilde.SSH.KeyProvider

  @host_key_name "ssh_host_rsa_key"

  @impl true
  def ensure_system_dir(path, _opts \\ []) when is_binary(path) do
    with :ok <- File.mkdir_p(path),
         :ok <- ensure_host_key(Path.join(path, @host_key_name)) do
      {:ok, path}
    end
  end

  @doc "Ensures a PEM encoded RSA host key exists at `path`."
  @spec ensure_host_key(Path.t()) :: :ok | {:error, File.posix()}
  def ensure_host_key(path) when is_binary(path) do
    if File.exists?(path) do
      :ok
    else
      write_host_key(path)
    end
  end

  defp write_host_key(path) do
    key = :public_key.generate_key({:rsa, 2048, 65_537})
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, key)])

    case File.write(path, pem) do
      :ok -> File.chmod(path, 0o600)
      {:error, reason} -> {:error, reason}
    end
  end
end
