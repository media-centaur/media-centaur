defmodule MediaCentaur.Repo.DataMigrations.SeriesWatchPositions do
  @moduledoc """
  Fills the table the schema migration of the same name created, and
  restates each item progress row in its two facts, so that after the
  upgrade Play offers each profile the item it offered before — or, for a
  rewatch, the item after the one last finished.

  Before this version a profile's place in a series was guessed from its
  item rows: the most recently touched row, with `completed` doubling as
  "no viewing is in flight". Three steps, in this order:

  1. **Positions.** For each profile and series (a TV series or a movie
     collection) with a completed row, one
     `library_series_watch_positions` row, read from the rows as they
     stand. The position is the newest completed row by `last_watched_at`
     — or, where the item after that one is completed and an item with no
     row exists, the item before the first item with no row (an old item
     replayed in full did not move Play then, and does not now). When that
     first item with no row is the series' first item there is no position:
     Play offers the first item, as it did. A series whose every item is
     completed keeps its newest completed row — a rewatch, which now
     continues instead of starting over. Only items with a file are
     counted, as in the app's ordered set. `finished_at` is the newest
     completed row's time.
  2. **Offsets.** A completed row has no viewing in flight: its
     `position_seconds` goes to 0. Extras too.
  3. **Marks.** A row with `completed = 0`, an offset and a watch-history
     event for its profile and item is a replay that cleared the mark: the
     mark is set again and the offset stays, as the viewing in flight.

  The order carries meaning. Positions are read first, while `completed`
  still says which row was finished last; offsets are zeroed before the
  marks are restored, so a restored replay keeps its offset.

  The order key is frozen here as every migration freezes what it needs:
  `[pad5(season), pad5(episode)]` for an episode, `[ISO date or "",
  pad5(position)]` for a collection movie — `EpisodeOrder.order_key/2` and
  `MovieOrder.order_key/1` on the day this shipped.

  Raw SQL, nothing published: a completion is shared with other people
  only by the app's writers, never from here.

  This file is **append-only**. Never edit a shipped data migration.

  Run again, step 1 skips every profile and series that has a position and
  step 2 finds no offset on the rows it zeroed. Step 3 is not repeatable
  across step 2: after this migration a marked row with an offset is a
  viewing in flight, which a second run's step 2 would end. The migrator
  runs it once.
  """
  use Ecto.Migration

  # An item with a file: the join `Episodes.count_available_by_tv_series/1`
  # and `PresentableQueries` use.
  @has_file """
  EXISTS (
    SELECT 1 FROM library_playable_items item
    JOIN library_watched_files file ON file.playable_item_id = item.id
    WHERE item.container_type = ?1 AND item.container_id = container.id
  )
  """

  # Position-coupled with `series_items/2`: [series_id, first, second, item_id].
  @episodes """
  SELECT season.tv_series_id, season.season_number, container.episode_number, container.id
  FROM library_episodes container
  JOIN library_seasons season ON season.id = container.season_id
  WHERE season.tv_series_id IS NOT NULL AND season.season_number IS NOT NULL
    AND container.episode_number IS NOT NULL AND #{@has_file}
  """

  # Position-coupled with `series_items/2`: [series_id, first, second, item_id].
  @collection_movies """
  SELECT container.movie_series_id, COALESCE(container.date_published, ''),
         COALESCE(container.position, 0), container.id
  FROM library_movies container
  WHERE container.movie_series_id IS NOT NULL AND #{@has_file}
  """

  # Position-coupled with `rows_by_profile/1`: [profile_id, item_id, completed, at].
  # `last_watched_at` is NULL only on rows older than the column's writers;
  # such a row is dated by its last write.
  @progress_rows """
  SELECT progress.profile_id, item.container_id, progress.completed,
         COALESCE(progress.last_watched_at, progress.updated_at)
  FROM library_watch_progress progress
  JOIN library_playable_items item ON item.id = progress.playable_item_id
  WHERE item.container_type IN ('episode', 'movie')
  """

  @insert_position """
  INSERT INTO library_series_watch_positions
    (id, profile_id, series_type, series_id, order_key, finished_at, inserted_at, updated_at)
  VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7)
  ON CONFLICT (profile_id, series_id) DO NOTHING
  """

  @zero_watch_offsets """
  UPDATE library_watch_progress SET position_seconds = 0.0
  WHERE completed = 1 AND position_seconds != 0
  """

  @zero_extra_offsets """
  UPDATE library_extra_progress SET position_seconds = 0.0
  WHERE completed = 1 AND position_seconds != 0
  """

  @restore_marks """
  UPDATE library_watch_progress SET completed = 1
  WHERE completed = 0 AND position_seconds > 0 AND EXISTS (
    SELECT 1 FROM watch_history_events event
    JOIN library_playable_items item ON item.id = library_watch_progress.playable_item_id
    WHERE event.profile_id = library_watch_progress.profile_id
      AND ((item.container_type = 'episode' AND event.episode_id = item.container_id)
        OR (item.container_type = 'movie' AND event.movie_id = item.container_id)
        OR (item.container_type = 'video_object' AND event.video_object_id = item.container_id))
  )
  """

  def up, do: backfill(repo())

  def down, do: :ok

  @doc "The three steps, exposed for direct testing."
  def backfill(repo) do
    insert_positions(repo)
    repo.query!(@zero_watch_offsets)
    repo.query!(@zero_extra_offsets)
    repo.query!(@restore_marks)
    :ok
  end

  defp insert_positions(repo) do
    rows_by_profile = rows_by_profile(repo)
    now = timestamp(repo)

    series =
      Map.merge(
        series_items(repo, "tv_series"),
        series_items(repo, "movie_series")
      )

    for {profile_id, profile_rows} <- rows_by_profile,
        {{series_type, series_id}, items} <- series,
        {order_key, finished_at} <- List.wrap(position(items, profile_rows)) do
      repo.query!(@insert_position, [
        Ecto.UUID.generate(),
        profile_id,
        series_type,
        series_id,
        JSON.encode!(order_key),
        finished_at,
        now
      ])
    end
  end

  # `%{{series_type, series_id} => [%{id, key}]}`, each list in story order.
  defp series_items(repo, "tv_series" = series_type) do
    repo
    |> rows(@episodes, ["episode"])
    |> group_items(series_type, fn season_number, episode_number ->
      [pad(season_number), pad(episode_number)]
    end)
  end

  defp series_items(repo, "movie_series" = series_type) do
    repo
    |> rows(@collection_movies, ["movie"])
    |> group_items(series_type, fn date_published, position -> [date_published, pad(position)] end)
  end

  defp group_items(rows, series_type, order_key) do
    rows
    |> Enum.group_by(
      fn [series_id, _first, _second, _item_id] -> {series_type, series_id} end,
      fn [_series_id, first, second, item_id] -> %{id: item_id, key: order_key.(first, second)} end
    )
    |> Map.new(fn {series, items} -> {series, Enum.sort_by(items, & &1.key)} end)
  end

  # `%{profile_id => %{item_id => %{completed, at}}}`. An item played in
  # parts has a row per part; the newest speaks for the item.
  defp rows_by_profile(repo) do
    repo
    |> rows(@progress_rows, [])
    |> Enum.reduce(%{}, fn [profile_id, item_id, completed, at], by_profile ->
      row = %{completed: completed == 1, at: at}

      Map.update(by_profile, profile_id, %{item_id => row}, fn by_item ->
        Map.update(by_item, item_id, row, &Enum.max_by([&1, row], fn candidate -> candidate.at end))
      end)
    end)
  end

  # `{order_key, finished_at}`, or nil for a series with no position. The
  # timestamps are ISO-8601 text and compare as text; rows stamped in the
  # same second (a season marked in one go) resolve to the later item.
  defp position(items, profile_rows) do
    rows = Enum.map(items, &Map.put(&1, :row, profile_rows[&1.id]))
    completed = Enum.filter(rows, &(&1.row && &1.row.completed))

    case Enum.max_by(completed, &{&1.row.at, &1.key}, fn -> nil end) do
      nil ->
        nil

      newest ->
        following = Enum.at(rows, Enum.find_index(rows, &(&1.id == newest.id)) + 1)
        following_completed? = following != nil and following.row != nil and following.row.completed
        first_without_row = Enum.find_index(rows, &(&1.row == nil))

        cond do
          following_completed? and first_without_row == 0 ->
            nil

          following_completed? and first_without_row != nil ->
            {Enum.at(rows, first_without_row - 1).key, newest.row.at}

          true ->
            {newest.key, newest.row.at}
        end
    end
  end

  # "Now" in the adapter's own text form for a `:utc_datetime` column.
  defp timestamp(repo) do
    [[now]] = rows(repo, "SELECT strftime('%Y-%m-%dT%H:%M:%SZ', 'now')", [])
    now
  end

  defp rows(repo, sql, params), do: repo.query!(sql, params).rows

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(5, "0")
end
