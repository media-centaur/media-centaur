defmodule MediaCentaur.Repo.Migrations.ExtraProgressPerProfile do
  @moduledoc """
  Extra progress belongs to a profile (ADR-078, phase 2): the rebuild of
  `library_extra_progress` with `profile_id`, every existing row the
  oldest profile's, unique on `(profile_id, extra_id)`. The copy fills the
  column, so no UPDATE. The extra FK gains `ON DELETE CASCADE` on the way:
  the original had none, and only the whole-library `EntityCascade.destroy_all!/0`
  emptied this table before its extras — a per-container `destroy!/1` of
  an extra with progress would have hit the FK. `extra_id` keeps its own
  index for that cascade, as every FK child column has. Not reversible.
  """
  use Ecto.Migration

  def up do
    create table(:library_extra_progress_next, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :extra_id, references(:library_extras, type: :uuid, on_delete: :delete_all), null: false
      add :profile_id, references(:profiles, type: :uuid, on_delete: :delete_all), null: false
      add :position_seconds, :float
      add :duration_seconds, :float
      add :completed, :boolean
      add :last_watched_at, :utc_datetime

      timestamps(type: :utc_datetime_usec)
    end

    execute """
    INSERT INTO library_extra_progress_next
      (id, extra_id, profile_id, position_seconds, duration_seconds, completed, last_watched_at,
       inserted_at, updated_at)
    SELECT id, extra_id, (SELECT id FROM profiles ORDER BY inserted_at, id LIMIT 1),
           position_seconds, duration_seconds, completed, last_watched_at, inserted_at, updated_at
    FROM library_extra_progress
    """

    drop table(:library_extra_progress)
    rename table(:library_extra_progress_next), to: table(:library_extra_progress)
    create unique_index(:library_extra_progress, [:profile_id, :extra_id])
    create index(:library_extra_progress, [:extra_id])
  end

  def down do
    raise Ecto.MigrationError,
          "extra_progress_per_profile is not reversible — rows of several profiles would collapse onto one extra_id"
  end
end
