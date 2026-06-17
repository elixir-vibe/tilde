defmodule Tilde.Storage.Schema.Event do
  @moduledoc "Canonical durable session event row."

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tilde_session_events" do
    field(:session_id, :string)
    field(:event_index, :integer)
    field(:event_type, :string)
    field(:payload, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)
    field(:inserted_at, :utc_datetime_usec)
  end
end
