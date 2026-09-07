defmodule MediaCentaur.Repo.Migrations.TitleIntentsHoldTheRung do
  @moduledoc """
  Collapses the two representations of one idea — "what should the app do
  about this title" — into one authored record.

  Before this, a person's intent lived in two rows: presence in
  `watchlist_items` meant "on my list", and `release_tracking_items.
  tracking_mode` meant "and this is what to do about its releases". Two
  rows for one fact needed a listener, a reconcile pass and a `Reasons`
  module to keep them agreeing, and an invariant ("every active tracked
  title is listed") that a migration had to prove on real data.

  Now `title_intents.rung` is the whole ladder and a tracked title is
  derived from it:

  | was | becomes |
  |---|---|
  | listed, no tracked title | `list` |
  | `tracking_mode = 'watch'` | `follow` |
  | `tracking_mode = 'ask'` | `ask` |
  | `tracking_mode = 'grab'` | `grab` |
  | `tracking_mode = 'global'` | `default` |
  | `tracking_mode = 'none'` | `list` — an explicit Off that is still listed |

  **Off becomes the absence of a record**, so the durable-disarm row
  disappears with the thing it existed to veto: nothing but a person can
  put a title on the ladder any more, so nothing can silently re-arm one.

  ## The behaviour change on upgrade

  Every tracked title with no `title_intents` row **stops being tracked**.
  Those are the titles the app started following on its own — the library
  auto-track, the "Download all" bolt-on, the quality-acceptance side
  effect — and nobody asked for them. This is the campaign's decision
  (`campaigns/tracking-is-a-persons-act.md`) and it belongs in the
  CHANGELOG in plain words, not as a refactor note.

  Movie *collection* trackers go with them: their `tmdb_id` is a TMDB
  collection id, which lives in a different namespace from a film's, so
  they can never have had a listing. Their only writer was `Scanner`,
  which had no caller.

  The sweep runs here rather than as a data migration because data
  migrations run *after* schema migrations, by which point
  `tracking_mode` is gone.
  """
  use Ecto.Migration

  @backfill_rung """
  UPDATE title_intents
  SET rung = COALESCE(
    (
      SELECT CASE i.tracking_mode
        WHEN 'watch' THEN 'follow'
        WHEN 'ask' THEN 'ask'
        WHEN 'grab' THEN 'grab'
        WHEN 'global' THEN 'default'
        ELSE 'list'
      END
      FROM release_tracking_items i
      WHERE i.tmdb_id = title_intents.tmdb_id
        AND i.media_type = title_intents.media_type
    ),
    'list'
  )
  """

  @sweep_unasked """
  DELETE FROM release_tracking_items
  WHERE NOT EXISTS (
    SELECT 1 FROM title_intents t
    WHERE t.tmdb_id = release_tracking_items.tmdb_id
      AND t.media_type = release_tracking_items.media_type
  )
  """

  def up do
    rename(table(:watchlist_items), to: table(:title_intents))

    alter table(:title_intents) do
      add :rung, :text, null: false, default: "list"
    end

    # The rung must carry its meaning before the column holding the old
    # half of it is dropped; nothing later could reconstruct it.
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute(@backfill_rung)
    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute(@sweep_unasked)

    # SQLite refuses to drop a column an index still names.
    drop_if_exists index(:release_tracking_items, [:tracking_mode])

    alter table(:release_tracking_items) do
      remove :tracking_mode
    end
  end

  def down do
    alter table(:release_tracking_items) do
      add :tracking_mode, :text
    end

    # credo:disable-for-next-line MediaCentaur.Credo.Checks.RowMutationInSchemaMigration
    execute("""
    UPDATE release_tracking_items
    SET tracking_mode = COALESCE(
      (
        SELECT CASE t.rung
          WHEN 'follow' THEN 'watch'
          WHEN 'ask' THEN 'ask'
          WHEN 'grab' THEN 'grab'
          WHEN 'default' THEN 'global'
          ELSE 'none'
        END
        FROM title_intents t
        WHERE t.tmdb_id = release_tracking_items.tmdb_id
          AND t.media_type = release_tracking_items.media_type
      ),
      'global'
    )
    """)

    create index(:release_tracking_items, [:tracking_mode])

    alter table(:title_intents) do
      remove :rung
    end

    rename(table(:title_intents), to: table(:watchlist_items))
  end
end
