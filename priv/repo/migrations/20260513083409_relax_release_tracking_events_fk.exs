defmodule MediaCentarr.Repo.Migrations.RelaxReleaseTrackingEventsFk do
  use Ecto.Migration

  # Events carry a denormalized `item_name` so they survive item deletion
  # (see the 2026-04-04 denormalize migration). That intent never reached
  # the FK constraint — `item_id` was still `on_delete: :delete_all`, which
  # silently wipes the audit row when an item is removed (e.g. when a
  # tracked movie lands in the library and tracking is auto-completed).
  #
  # SQLite can't ALTER a FK in place, so we do the standard table rebuild:
  # create the new shape, copy data, swap.
  def up do
    execute("PRAGMA foreign_keys = OFF")

    create table(:release_tracking_events_new, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :nilify_all),
        null: true

      add :event_type, :string, null: false
      add :description, :string, null: false
      add :metadata, :map, default: %{}
      add :item_name, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    execute("""
    INSERT INTO release_tracking_events_new
      (id, item_id, event_type, description, metadata, item_name, inserted_at)
    SELECT id, item_id, event_type, description, metadata, item_name, inserted_at
    FROM release_tracking_events
    """)

    drop table(:release_tracking_events)

    rename table(:release_tracking_events_new), to: table(:release_tracking_events)

    create index(:release_tracking_events, [:item_id])

    execute("PRAGMA foreign_keys = ON")
  end

  def down do
    execute("PRAGMA foreign_keys = OFF")

    create table(:release_tracking_events_old, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true

      add :item_id, references(:release_tracking_items, type: :uuid, on_delete: :delete_all),
        null: false

      add :event_type, :string, null: false
      add :description, :string, null: false
      add :metadata, :map, default: %{}
      add :item_name, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    execute("""
    INSERT INTO release_tracking_events_old
      (id, item_id, event_type, description, metadata, item_name, inserted_at)
    SELECT id, item_id, event_type, description, metadata, item_name, inserted_at
    FROM release_tracking_events
    WHERE item_id IS NOT NULL
    """)

    drop table(:release_tracking_events)

    rename table(:release_tracking_events_old), to: table(:release_tracking_events)

    create index(:release_tracking_events, [:item_id])

    execute("PRAGMA foreign_keys = ON")
  end
end
