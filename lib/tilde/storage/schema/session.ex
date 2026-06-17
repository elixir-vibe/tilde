defmodule Tilde.Storage.Schema.Session do
  @moduledoc "Durable session metadata row."

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tilde_sessions" do
    field(:title, :string)
    field(:metadata, :map, default: %{})
    field(:archived_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end
end
