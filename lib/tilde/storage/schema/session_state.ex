defmodule Tilde.Storage.Schema.SessionState do
  @moduledoc "Durable resumable local session draft state."

  use Ecto.Schema

  @primary_key {:session_id, :string, autogenerate: false}
  schema "tilde_session_state" do
    field(:input_value, :string)
    field(:input_cursor, :integer)
    field(:selected_suggestion, :integer)
    field(:metadata, :map, default: %{})
    field(:updated_at, :utc_datetime_usec)
  end
end
