defmodule Tilde.Demo.Environment do
  @moduledoc "Environment loading for standalone demo tasks."

  @doc "Loads conventional dotenv files into the process environment."
  @spec load() :: :ok | {:error, term()}
  def load do
    with {:module, Dotenvy} <- Code.ensure_loaded(Dotenvy),
         {:ok, env} <- Dotenvy.source(sources()) do
      System.put_env(env)
      :ok
    else
      {:error, _reason} = error -> error
      _missing_dotenvy -> :ok
    end
  end

  defp sources do
    env = Atom.to_string(Mix.env())

    [
      System.get_env(),
      ".env",
      "#{env}.env",
      ".env.local",
      "#{env}.override.env",
      System.get_env()
    ]
  end
end
