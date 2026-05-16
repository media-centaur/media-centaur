defmodule MediaCentarr.Repo.Migrations.CreatePlayableItems do
  use Ecto.Migration

  def change do
    create table(:library_playable_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :container_type, :string, null: false
      add :container_id, :binary_id, null: false
      add :position, :integer
      add :duration_seconds, :integer
      add :name, :string
      timestamps()
    end

    # Discriminator pair (campaign decision 2026-05-15). No DB-level FK
    # enforcement on `container_id` — app-level integrity is enforced at
    # the write seam in `MediaCentarr.Library.Inbound`.
    #
    # Unique on `(container_type, container_id, position)` so Task B/G can
    # use changeset `unique_constraint` errors for race-loss recovery
    # rather than pre-check + insert (closes the TOCTOU window). The same
    # index supports the `(container_type, container_id)` lookup prefix, so
    # a separate non-unique index would be redundant. The default Ecto-
    # derived name (`library_playable_items_container_type_container_id_position_index`)
    # matches the synthetic name the SQLite adapter surfaces in
    # constraint errors — see `MediaCentarr.Library.PlayableItem.create_changeset/1`.
    create unique_index(:library_playable_items, [:container_type, :container_id, :position])
  end
end
