defmodule Tilde.Storage.Repo.Migrations.CreateTildeStorage do
  use Ecto.Migration

  def change do
    create table(:tilde_sessions, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :metadata, :map
      add :archived_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create table(:tilde_session_events, primary_key: false) do
      add :id, :string, primary_key: true
      add :session_id, :string, null: false
      add :event_index, :integer, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:tilde_session_events, [:session_id, :event_index])
    create index(:tilde_session_events, [:session_id, :event_type])

    create table(:tilde_session_blocks, primary_key: false) do
      add :id, :string, primary_key: true
      add :session_id, :string, null: false
      add :event_index, :integer, null: false
      add :block_index, :integer, null: false
      add :kind, :string, null: false
      add :role, :string
      add :text, :text, null: false
      add :tool_name, :string
      add :metadata, :map
      add :occurred_at, :utc_datetime_usec, null: false
    end

    create index(:tilde_session_blocks, [:session_id, :event_index])
    create index(:tilde_session_blocks, [:kind])
    create index(:tilde_session_blocks, [:tool_name])

    create table(:tilde_session_state, primary_key: false) do
      add :session_id, :string, primary_key: true
      add :input_value, :text
      add :input_cursor, :integer
      add :selected_suggestion, :integer
      add :metadata, :map
      add :updated_at, :utc_datetime_usec, null: false
    end
  end
end
