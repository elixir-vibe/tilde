defmodule Tilde.Dev do
  @moduledoc "Development-only browser diagnostics toggles."

  @truthy ~w(1 true yes on)

  @doc "Returns true when browser devtools UI may be shown."
  @spec enabled?() :: boolean()
  def enabled? do
    config_enabled?() or env_enabled?() or default_enabled?()
  end

  defp config_enabled?, do: Application.get_env(:tilde, :devtools, false) == true

  defp default_enabled?,
    do: Application.get_env(:tilde, :devtools, Mix.env() in [:dev, :test]) == true

  defp env_enabled? do
    "TILDE_DEVTOOLS"
    |> System.get_env("")
    |> String.downcase()
    |> then(&(&1 in @truthy))
  end
end
