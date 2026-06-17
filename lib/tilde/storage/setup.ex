defmodule Tilde.Storage.Setup do
  @moduledoc "Setup helpers for Tilde's Ecto-backed storage repository."

  alias Ecto.Migrator
  alias Tilde.Storage.Repo

  @doc "Runs all pending storage migrations through Ecto."
  @spec migrate(keyword()) :: {:ok, [integer()]} | {:error, term()}
  def migrate(opts \\ []) do
    repo = Keyword.get(opts, :repo, Repo)
    migrations_path = Keyword.get(opts, :migrations_path, migrations_path())

    {:ok, _apps} = Application.ensure_all_started(:ecto_sql)

    case Migrator.with_repo(repo, fn repo ->
           Migrator.run(repo, migrations_path, :up, all: true)
         end) do
      {:ok, versions, _apps} -> {:ok, versions}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error in [
      DBConnection.ConnectionError,
      Ecto.ChangeError,
      Ecto.InvalidChangesetError,
      Ecto.MigrationError,
      Ecto.QueryError,
      RuntimeError,
      ArgumentError
    ] ->
      {:error, error}
  end

  @doc "Returns the storage migrations path."
  @spec migrations_path() :: String.t()
  def migrations_path do
    :tilde
    |> :code.priv_dir()
    |> to_string()
    |> Path.join("repo/migrations")
  end
end
