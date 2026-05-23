defmodule MediaCentaur.Repo.Migrations.RestoreSeasonUniqueIndex do
  @moduledoc """
  Restores the unique index on `library_seasons (tv_series_id, season_number)`.

  The Library Schema v2 rename (`seasons` → `library_seasons`,
  `entity_id` → `tv_series_id`) dropped the old
  `seasons_unique_entity_season_index` and never re-created an equivalent
  on the new column. Without the DB guard, a burst of episodes for one
  new season races in `Library.find_or_insert_by/3` (read-then-write with
  no constraint) and inserts duplicate `Season` rows. Every later
  `Repo.get_by/2` then raises `MultipleResultsError`, wedging the whole
  series' imports. (Episodes kept their unique index across the rename,
  so they never duplicated.)

  This migration:

  1. De-duplicates any existing duplicate seasons — re-points each
     duplicate's episodes and season-scoped extras onto the keeper (the
     season carrying the most episodes), then deletes the now-empty
     duplicate. Raises loudly if two duplicates of one season share an
     episode number (merging would violate the episode unique index);
     that pathological case must be resolved by hand rather than guessed
     at here.
  2. Normalises the episode unique index name. Production carries the
     legacy `episodes_unique_season_episode_index` (renamed in place);
     freshly-migrated databases carry the Ecto default
     `library_episodes_season_id_episode_number_index`. Converging both
     onto the default lets the `Episode` changeset declare one
     `unique_constraint` name that matches everywhere.
  3. Creates the season unique index with the Ecto default name so the
     `Season` changeset's `unique_constraint` matches it.

  Irreversible (the de-dup deletes rows); `down/0` only drops the index.
  """
  use Ecto.Migration

  def up do
    dedup_seasons!()

    # Normalise the episode unique index name across drifted databases.
    drop_if_exists unique_index(:library_episodes, [:season_id, :episode_number],
                     name: "episodes_unique_season_episode_index"
                   )

    create_if_not_exists unique_index(:library_episodes, [:season_id, :episode_number])

    # Restore the season guard that the v2 rename dropped.
    create_if_not_exists unique_index(:library_seasons, [:tv_series_id, :season_number])
  end

  def down do
    drop_if_exists unique_index(:library_seasons, [:tv_series_id, :season_number])
  end

  defp dedup_seasons! do
    Enum.each(duplicate_groups(), fn [tv_series_id, season_number] ->
      [keeper | duplicates] = season_ids_ranked(tv_series_id, season_number)

      Enum.each(duplicates, fn duplicate ->
        guard_no_episode_collision!(keeper, duplicate, tv_series_id, season_number)

        repo().query!("UPDATE library_episodes SET season_id = ? WHERE season_id = ?", [
          keeper,
          duplicate
        ])

        repo().query!(
          "UPDATE library_extras SET owner_id = ? WHERE owner_type = 'season' AND owner_id = ?",
          [keeper, duplicate]
        )

        repo().query!("DELETE FROM library_seasons WHERE id = ?", [duplicate])
      end)
    end)
  end

  defp duplicate_groups do
    repo().query!("""
    SELECT tv_series_id, season_number
    FROM library_seasons
    WHERE tv_series_id IS NOT NULL AND season_number IS NOT NULL
    GROUP BY tv_series_id, season_number
    HAVING COUNT(*) > 1
    """).rows
  end

  # Keeper first: the season carrying the most episodes (preserve the most
  # data), tie-broken by id for determinism.
  defp season_ids_ranked(tv_series_id, season_number) do
    result =
      repo().query!(
        """
        SELECT s.id
        FROM library_seasons s
        WHERE s.tv_series_id = ? AND s.season_number = ?
        ORDER BY (SELECT COUNT(*) FROM library_episodes e WHERE e.season_id = s.id) DESC, s.id ASC
        """,
        [tv_series_id, season_number]
      )

    List.flatten(result.rows)
  end

  defp guard_no_episode_collision!(keeper, duplicate, tv_series_id, season_number) do
    result =
      repo().query!(
        """
        SELECT episode_number
        FROM library_episodes
        WHERE season_id = ?
          AND episode_number IN (SELECT episode_number FROM library_episodes WHERE season_id = ?)
        """,
        [duplicate, keeper]
      )

    collisions = List.flatten(result.rows)

    if collisions != [] do
      raise """
      Cannot auto-dedup duplicate season (tv_series_id=#{tv_series_id}, \
      season_number=#{season_number}): episode number(s) #{inspect(collisions)} \
      exist on both the keeper and a duplicate season, so merging would violate \
      the episode unique index. Resolve these episodes by hand, then re-run.
      """
    end
  end
end
