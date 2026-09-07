defmodule MediaCentaur.Repo.Migrations.MoveDownloadParamsToAcquisition do
  @moduledoc """
  Per-title download params — the quality floor and ceiling and the 4K
  patience window — move off `release_tracking_items` and into
  Acquisition's own `title_download_params`, keyed by TMDB identity.

  They were always acquisition settings: `DropPlanner` and
  `Plans.resolve_title_bounds` are their only readers, and release
  tracking merely held the columns. That misplacement had a visible
  consequence — "Accept lower quality" on a plan board had to *create a
  tracked title* to have somewhere to write, so a person adjusting a
  quality floor silently started tracking the show. Keyed by identity
  instead of by tracked title, the params outlive tracking and can be set
  for a title nobody tracks.

  `prefer_season_packs` is deliberately not carried over. It was written
  by `update_automation/2` and read by nothing; the season-pack lever the
  planner actually consults is the global `pack_min_fit` setting.
  """
  use Ecto.Migration

  # UUID v4 synthesised from randomblob — SQLite has no uuid(); same
  # shape as `TrackingModeReplacesStatusAndSource`.
  @uuid_v4 "lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))), 2) || '-' || substr('89ab', abs(random()) % 4 + 1, 1) || substr(lower(hex(randomblob(2))), 2) || '-' || lower(hex(randomblob(6)))"

  # Only rows that actually carry a preference become rows here: an
  # absent record and an all-null record mean the same thing (inherit the
  # global default), and the smaller table is the honest one.
  @backfill """
  INSERT INTO title_download_params (id, tmdb_id, media_type, params, inserted_at, updated_at)
  SELECT
    #{@uuid_v4},
    i.tmdb_id,
    i.media_type,
    json_object(
      'min_quality', i.min_quality,
      'max_quality', i.max_quality,
      'quality_4k_patience_hours', i.quality_4k_patience_hours
    ),
    i.inserted_at,
    i.updated_at
  FROM release_tracking_items i
  WHERE i.min_quality IS NOT NULL
     OR i.max_quality IS NOT NULL
     OR i.quality_4k_patience_hours IS NOT NULL
  """

  def up do
    create table(:title_download_params, primary_key: false) do
      add :id, :uuid, null: false, primary_key: true
      add :tmdb_id, :integer, null: false
      add :media_type, :text, null: false
      add :params, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:title_download_params, [:tmdb_id, :media_type])

    # The params must exist under their new owner before the columns
    # holding them are dropped; nothing later could reconstruct them.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute(@backfill)

    alter table(:release_tracking_items) do
      remove :min_quality
      remove :max_quality
      remove :quality_4k_patience_hours
      remove :prefer_season_packs
    end
  end

  def down do
    alter table(:release_tracking_items) do
      add :min_quality, :text
      add :max_quality, :text
      add :quality_4k_patience_hours, :integer
      add :prefer_season_packs, :boolean, default: false
    end

    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE release_tracking_items
    SET min_quality = (
          SELECT json_extract(p.params, '$.min_quality') FROM title_download_params p
          WHERE p.tmdb_id = release_tracking_items.tmdb_id
            AND p.media_type = release_tracking_items.media_type
        ),
        max_quality = (
          SELECT json_extract(p.params, '$.max_quality') FROM title_download_params p
          WHERE p.tmdb_id = release_tracking_items.tmdb_id
            AND p.media_type = release_tracking_items.media_type
        ),
        quality_4k_patience_hours = (
          SELECT json_extract(p.params, '$.quality_4k_patience_hours') FROM title_download_params p
          WHERE p.tmdb_id = release_tracking_items.tmdb_id
            AND p.media_type = release_tracking_items.media_type
        )
    """)

    drop table(:title_download_params)
  end
end
