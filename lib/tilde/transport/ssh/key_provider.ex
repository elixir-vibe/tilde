defmodule Tilde.Transport.SSH.KeyProvider do
  @moduledoc """
  Behaviour for SSH daemon host key providers.
  """

  @callback ensure_system_dir(Path.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
end
