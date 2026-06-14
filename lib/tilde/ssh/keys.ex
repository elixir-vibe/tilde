defmodule Tilde.SSH.Keys do
  @moduledoc """
  SSH host key provider facade.

  The concrete provider is configured with `:tilde, :ssh_key_provider` and
  defaults to `Tilde.SSH.KeyProvider.PublicKey`.
  """

  @default_provider Tilde.SSH.KeyProvider.PublicKey

  @doc "Ensures a demo SSH `system_dir` exists with a host key."
  @spec ensure_system_dir(Path.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def ensure_system_dir(path, opts \\ []) when is_binary(path) do
    provider().ensure_system_dir(path, opts)
  end

  @doc "Returns the configured SSH key provider."
  @spec provider() :: module()
  def provider do
    Application.get_env(:tilde, :ssh_key_provider, @default_provider)
  end
end
