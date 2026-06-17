defmodule Tilde.Storage.Schema.Block do
  @moduledoc "Searchable projection row derived from session events."

  use Ecto.Schema

  @primary_key {:id, :string, autogenerate: false}
  schema "tilde_session_blocks" do
    field(:session_id, :string)
    field(:event_index, :integer)
    field(:block_index, :integer)
    field(:kind, :string)
    field(:role, :string)
    field(:text, :string)
    field(:tool_name, :string)
    field(:metadata, :map, default: %{})
    field(:occurred_at, :utc_datetime_usec)
  end
end
