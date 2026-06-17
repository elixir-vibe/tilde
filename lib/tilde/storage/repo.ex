defmodule Tilde.Storage.Repo do
  @moduledoc "Ecto repo for durable Tilde storage backed by QuackDB."

  use Ecto.Repo,
    otp_app: :tilde,
    adapter: Ecto.Adapters.QuackDB
end
