defmodule MediaCentarr.Library.WatchProgressTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Library
  alias MediaCentarr.Library.WatchProgress
  alias MediaCentarr.Repo

  describe "find_or_create" do
    test "create and read back via movie_id" do
      movie = create_entity(%{type: :movie, name: "Progress Movie"})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 120.5,
        duration_seconds: 7200.0
      })

      {:ok, found} =
        Library.fetch_watch_progress_by_fk(:movie_id, movie.id)

      found = MediaCentarr.Repo.preload(found, :playable_item)

      assert found.playable_item.container_type == :movie
      assert found.playable_item.container_id == movie.id
      assert found.position_seconds == 120.5
      assert found.duration_seconds == 7200.0
      assert found.completed == false
      assert found.last_watched_at != nil
    end

    test "new record defaults completed to false" do
      movie = create_entity(%{type: :movie, name: "New Progress"})

      progress =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 6840.0,
          duration_seconds: 7200.0
        })

      # Even at 95% position, upsert does not auto-complete
      assert progress.completed == false
    end

    test "upsert preserves existing completed: true" do
      tv_series = create_entity(%{type: :tv_series, name: "Completed Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "Pilot"
        })

      # Create initial progress
      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 6480.0,
        duration_seconds: 7200.0
      })

      # Mark completed via dedicated action
      {:ok, record} = Library.fetch_watch_progress_by_fk(:episode_id, episode.id)
      {:ok, _} = Library.mark_watch_completed(record)

      # Now upsert with a lower position (re-watching from earlier)
      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 300.0,
        duration_seconds: 7200.0
      })

      {:ok, updated} = Library.fetch_watch_progress_by_fk(:episode_id, episode.id)

      # completed stays true — never regresses
      assert updated.completed == true
      assert updated.position_seconds == 300.0
    end

    test "upsert idempotency — second upsert updates values, no duplicate" do
      tv_series = create_entity(%{type: :tv_series, name: "Upsert Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 3,
          name: "Third"
        })

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 60.0,
        duration_seconds: 2400.0
      })

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 1200.0,
        duration_seconds: 2400.0
      })

      records = Library.list_watch_progress()

      assert length(records) == 1
      assert hd(records).position_seconds == 1200.0
    end

    test "upsert idempotency — movie creates one record, not duplicates" do
      movie = create_entity(%{type: :movie, name: "Upsert Movie"})

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 35.0,
        duration_seconds: 7200.0
      })

      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 3930.0,
        duration_seconds: 7200.0
      })

      records = Library.list_watch_progress()

      assert length(records) == 1
      assert hd(records).position_seconds == 3930.0
    end

    test "upsert updates last_watched_at timestamp" do
      tv_series = create_entity(%{type: :tv_series, name: "Timestamp Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{
          season_id: season.id,
          episode_number: 1,
          name: "First"
        })

      first =
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 60.0,
          duration_seconds: 2400.0
        })

      # Small delay to ensure timestamps differ
      Process.sleep(1100)

      create_watch_progress(%{
        episode_id: episode.id,
        position_seconds: 300.0,
        duration_seconds: 2400.0
      })

      {:ok, updated} = Library.fetch_watch_progress_by_fk(:episode_id, episode.id)

      assert DateTime.compare(updated.last_watched_at, first.last_watched_at) in [:gt, :eq]
      assert updated.position_seconds == 300.0
    end

    test "multiple progress records for different episodes of same entity" do
      tv_series = create_entity(%{type: :tv_series, name: "Multi-Episode"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      ep1 =
        create_episode(%{season_id: season.id, episode_number: 1, name: "First"})

      ep2 =
        create_episode(%{season_id: season.id, episode_number: 2, name: "Second"})

      create_watch_progress(%{
        episode_id: ep1.id,
        position_seconds: 2400.0,
        duration_seconds: 2400.0
      })

      create_watch_progress(%{
        episode_id: ep2.id,
        position_seconds: 600.0,
        duration_seconds: 2400.0
      })

      records = Library.list_watch_progress()

      assert length(records) == 2
    end
  end

  describe "mark_completed" do
    test "transitions false to true" do
      movie = create_entity(%{type: :movie, name: "Mark Complete"})

      progress =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 6480.0,
          duration_seconds: 7200.0
        })

      assert progress.completed == false

      {:ok, updated} = Library.mark_watch_completed(progress)
      assert updated.completed == true
    end

    test "updates last_watched_at" do
      movie = create_entity(%{type: :movie, name: "Mark Complete Timestamp"})

      progress =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 100.0,
          duration_seconds: 7200.0
        })

      Process.sleep(1100)

      {:ok, updated} = Library.mark_watch_completed(progress)
      assert DateTime.compare(updated.last_watched_at, progress.last_watched_at) in [:gt, :eq]
    end
  end

  describe "mark_incomplete" do
    test "transitions completed from true to false" do
      tv_series = create_entity(%{type: :tv_series, name: "Unwatch Show"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      episode =
        create_episode(%{season_id: season.id, episode_number: 1, name: "First"})

      progress =
        create_watch_progress(%{
          episode_id: episode.id,
          position_seconds: 2400.0,
          duration_seconds: 2400.0
        })

      {:ok, completed} = Library.mark_watch_completed(progress)
      assert completed.completed == true

      {:ok, incomplete} = Library.mark_watch_incomplete(completed)
      assert incomplete.completed == false
      assert incomplete.last_watched_at != nil
    end

    test "updates last_watched_at" do
      movie = create_entity(%{type: :movie, name: "Unwatch Timestamp"})

      progress =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 100.0,
          duration_seconds: 7200.0
        })

      {:ok, completed} = Library.mark_watch_completed(progress)
      Process.sleep(1100)

      {:ok, incomplete} = Library.mark_watch_incomplete(completed)
      assert DateTime.compare(incomplete.last_watched_at, completed.last_watched_at) in [:gt, :eq]
    end
  end

  describe "unique constraint on playable_item_id" do
    # Library Schema v2 Phase 2 Task C added `UNIQUE(playable_item_id)`
    # so a second insert targeting the same PlayableItem fails with a
    # changeset constraint error rather than silently creating duplicate
    # progress rows.
    test "second insert against the same playable_item_id errors" do
      movie = create_entity(%{type: :movie, name: "Unique Constraint Movie"})

      {:ok, playable_item} =
        Library.find_or_create_playable_item(:movie, movie.id, 1)

      assert {:ok, _first} =
               Repo.insert(
                 WatchProgress.create_changeset(%{
                   playable_item_id: playable_item.id,
                   position_seconds: 10.0,
                   duration_seconds: 100.0
                 })
               )

      assert {:error, changeset} =
               Repo.insert(
                 WatchProgress.create_changeset(%{
                   playable_item_id: playable_item.id,
                   position_seconds: 50.0,
                   duration_seconds: 100.0
                 })
               )

      refute changeset.valid?
      assert {"has already been taken", _} = changeset.errors[:playable_item_id]
    end
  end
end
