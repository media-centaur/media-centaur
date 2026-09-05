defmodule MediaCentaur.Repo.Migrations.GeneralizeRecommendationsToActivities do
  @moduledoc """
  The `recommendations` table becomes `activities`: one row per signed
  statement of any kind — recommendation, watched, tracking — keyed by
  `(author_pubkey, kind, tmdb_id, media_type)`. Existing rows are all
  recommendations (`kind` defaults to it); `recommended_at` becomes the
  kind-neutral `acted_at`; `episode` carries a watched TV series' episode.
  A watchlist row's provenance column follows: `recommendation_id` →
  `activity_id`.

  SQLite renames are in-place and idempotent for a skipped-release
  upgrade: the schema migration runs before any data migration and there
  is no backfill to tolerate.
  """
  use Ecto.Migration

  def change do
    rename table(:recommendations), to: table(:activities)

    alter table(:activities) do
      add :kind, :text, null: false, default: "recommendation"
      add :episode, :map
    end

    rename table(:activities), :recommended_at, to: :acted_at

    # SQLite keeps an index's name across a table rename, and Ecto derives
    # the constraint name a changeset reports from the *new* table name —
    # every index is rebuilt under it.
    drop unique_index(:recommendations, [:event_id])
    drop unique_index(:recommendations, [:author_pubkey, :tmdb_id, :media_type])
    drop index(:recommendations, [:recommended_at])
    create unique_index(:activities, [:event_id])
    create unique_index(:activities, [:author_pubkey, :kind, :tmdb_id, :media_type])
    create index(:activities, [:acted_at])

    rename table(:watchlist_items), :recommendation_id, to: :activity_id
  end
end
