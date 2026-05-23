defmodule MediaCentaur.Repo.Migrations.DenormalizeReleaseTrackingEvents do
  use Ecto.Migration

  def change do
    # SQLite doesn't enforce FK constraints at the schema level the same way,
    # so we just need to add the new column and make item_id nullable.
    # The Ecto schema no longer has `belongs_to`, so no FK is followed.
    alter table(:release_tracking_events) do
      add :item_name, :string
    end

    # Backfill item_name from existing items
    execute(
      """
      UPDATE release_tracking_events
      SET item_name = (
        SELECT name FROM release_tracking_items
        WHERE release_tracking_items.id = release_tracking_events.item_id
      )
      """,
      ""
    )
  end
end
