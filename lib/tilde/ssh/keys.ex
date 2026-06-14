defmodule Tilde.SSH.Keys do
  @moduledoc """
  Demo SSH host key generation using Erlang/OTP `:public_key`.

  The generated key is a PEM encoded RSA private key suitable for Erlang's SSH
  daemon `system_dir`. No external `ssh-keygen` command is used.
  """

  @host_key_name "ssh_host_rsa_key"

  @doc "Ensures a demo SSH `system_dir` exists with a host key."
  @spec ensure_system_dir(Path.t()) :: {:ok, Path.t()} | {:error, File.posix()}
  def ensure_system_dir(path) when is_binary(path) do
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
