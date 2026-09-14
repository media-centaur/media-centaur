defmodule MediaCentaur.Repo.Migrations.DropReleaseTrackingEvents do
  @moduledoc """
  Drops the release-tracking event log (spec 2026-09-14, iteration 3).
  The log — "Now tracking", calendar diffs, "now in your library" — was
  read by one surface, the Recent activity section under a title, and
  that section is gone: the release dates readout says what is coming.
  Nothing else read the table, so the schema, the calendar differ that
  existed to write it, and its retention policy go with it.

  Down re-creates the table in its last shape (the relaxed-FK rebuild of
  2026-05-13); the rows themselves are not recoverable, and were never
  shown as more than eight lines.
  """
  use Ecto.Migration

  def up do
    drop table(:release_tracking_events)
  end

  def down do
    create table(:release_tracking_events, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :nilify_all),
        null: true

      add :event_type, :string, null: false
      add :description, :string, null: false
      add :metadata, :map, default: %{}
      add :item_name, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:release_tracking_events, [:item_id])
  end
end
