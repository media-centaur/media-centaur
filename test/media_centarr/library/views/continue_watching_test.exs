defmodule MediaCentarr.Library.Views.ContinueWatchingTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Views
  alias MediaCentarr.Library.Views.ContinueWatching
  alias MediaCentarr.Library.Views.ContinueWatchingItem
  alias MediaCentarr.Repo
  alias MediaCentarr.Topics

  @table :library_view_continue_watching

  defp seed_in_progress_movie(name, last_watched_at \\ nil) do
    movie = create_standalone_movie(%{name: name})
    record_present(create_linked_file(%{movie_id: movie.id}))

    progress =
      create_watch_progress(%{
        movie_id: movie.id,
        position_seconds: 30.0,
        duration_seconds: 100.0
      })

    if last_watched_at do
      progress
      |> Ecto.Changeset.change(last_watched_at: last_watched_at)
      |> Repo.update!()
    end

    movie
  end

  # ETS table is global; tests that exercise the cached path must clean
  # up so later tests fall back to the DB path with empty ETS.
  defp on_exit_clear_table do
    on_exit(fn ->
      case :ets.whereis(@table) do
        :undefined -> :ok
        _ref -> :ets.delete(@table)
      end
    end)
  end

  # Post-Phase-7 no-op (legacy hook from the library-presence-unification campaign).
  defp record_present(_file), do: :ok

  describe "Cache behaviour — relevant?/1" do
    test "accepts library entity-changed events" do
      assert ContinueWatching.relevant?({:entities_changed, %{entity_ids: ["x"]}})
    end

    test "accepts watch-history completion events" do
      assert ContinueWatching.relevant?({:watch_event_created, %{}})
    end

    test "accepts entity-progress updates so the bar stays live mid-playback" do
      assert ContinueWatching.relevant?({:entity_progress_updated, %{}})
    end

    test "accepts availability changes (file presence flips alter the result set)" do
      assert ContinueWatching.relevant?({:availability_changed, "/some/dir", :available})
      assert ContinueWatching.relevant?({:availability_changed, "/some/dir", :unavailable})
    end

    test "rejects unrelated messages" do
      refute ContinueWatching.relevant?(:something_else)
      refute ContinueWatching.relevant?({:playback_state_changed, %{}})
      refute ContinueWatching.relevant?({:extra_progress_updated, %{}})
      refute ContinueWatching.relevant?({:other, "payload"})
    end
  end

  describe "refresh_cache/0" do
    test "populates the ETS table with view-model structs in display order" do
      on_exit_clear_table()

      now = DateTime.utc_now(:second)
      seed_in_progress_movie("First Watched", DateTime.add(now, -3600, :second))
      seed_in_progress_movie("Second Watched", DateTime.add(now, -1800, :second))
      seed_in_progress_movie("Third Watched", now)

      assert :ok = ContinueWatching.refresh_cache()

      items = Views.continue_watching(limit: 10)

      assert length(items) == 3
      assert Enum.all?(items, &is_struct(&1, ContinueWatchingItem))

      # Most-recently-watched first.
      names = Enum.map(items, & &1.entity_name)
      assert names == ["Third Watched", "Second Watched", "First Watched"]
    end

    test "broadcasts {:library_view_updated, :continue_watching} after refresh" do
      on_exit_clear_table()

      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_views())

      seed_in_progress_movie("Some Movie")

      assert :ok = ContinueWatching.refresh_cache()

      assert_receive {:library_view_updated, :continue_watching}
    end

    test "is idempotent — repeat calls replace the snapshot, no leak" do
      on_exit_clear_table()

      seed_in_progress_movie("Movie A")
      assert :ok = ContinueWatching.refresh_cache()
      assert length(Views.continue_watching(limit: 10)) == 1

      seed_in_progress_movie("Movie B")
      assert :ok = ContinueWatching.refresh_cache()
      assert length(Views.continue_watching(limit: 10)) == 2

      # Refreshing without DB changes preserves the snapshot.
      assert :ok = ContinueWatching.refresh_cache()
      assert length(Views.continue_watching(limit: 10)) == 2
    end
  end

  describe "Views.continue_watching/1 — ETS path vs DB fallback" do
    test "falls back to DB query when the ETS table is absent" do
      seed_in_progress_movie("Cold Read")

      assert :undefined = :ets.whereis(@table)

      [item] = Views.continue_watching(limit: 5)
      assert item.entity_name == "Cold Read"
    end

    test "honours :limit on the ETS path" do
      on_exit_clear_table()

      Enum.each(1..5, fn i -> seed_in_progress_movie("Movie #{i}") end)
      assert :ok = ContinueWatching.refresh_cache()

      assert length(Views.continue_watching(limit: 3)) == 3
      assert length(Views.continue_watching(limit: 100)) == 5
    end

    test "honours :limit on the DB-fallback path" do
      Enum.each(1..5, fn i -> seed_in_progress_movie("Movie #{i}") end)

      assert :undefined = :ets.whereis(@table)

      assert length(Views.continue_watching(limit: 3)) == 3
    end
  end

  describe "equivalence with Library.list_in_progress/1" do
    # Until the legacy query path is removed (commit 3 of B), prove the
    # projection's view-model output mirrors the legacy map output for
    # representative DB state. A drift here would be a real regression.
    test "ETS-cached output matches Library.list_in_progress for the same DB state" do
      on_exit_clear_table()

      seed_in_progress_movie("Movie One")
      Process.sleep(5)
      seed_in_progress_movie("Movie Two")

      :ok = ContinueWatching.refresh_cache()

      legacy = Library.list_in_progress(limit: 10)
      cached = Views.continue_watching(limit: 10)

      assert length(legacy) == length(cached)

      Enum.each(Enum.zip(legacy, cached), fn {legacy_row, cached_item} ->
        assert legacy_row.entity_id == cached_item.entity_id
        assert legacy_row.entity_name == cached_item.entity_name
        assert legacy_row.progress_pct == cached_item.progress_pct
        assert legacy_row.last_episode_label == cached_item.last_episode_label
        assert legacy_row.backdrop_url == cached_item.backdrop_url
        assert legacy_row.logo_url == cached_item.logo_url
        assert legacy_row.last_watched_at == cached_item.last_watched_at
      end)
    end
  end

  describe "stale-read window — refresh reflects in-memory progress" do
    # Regression for Library Schema v2 Phase 3 Task E I-2: the
    # `MediaCentarr.Library.Progress.record/3` hot-path writes to the
    # in-memory ETS table only; the debounced flush lands seconds
    # later. Before the fix, `list_in_progress/1` (and therefore
    # `ContinueWatching.refresh_cache/0` and the DB-fallback path)
    # read straight from the persisted `library_watch_progress`
    # table, so the rendered progress bar lagged active playback by
    # one flush interval. The overlay in `Library.list_in_progress`
    # closes that window.

    alias MediaCentarr.Library.Progress

    @flush_interval_ms 60_000

    defp ensure_progress_worker! do
      case Process.whereis(Progress.Worker) do
        nil ->
          {:ok, _pid} =
            start_supervised(
              {Progress.Worker, [flush_interval_ms: @flush_interval_ms, name: Progress.Worker]}
            )

          :ok

        _pid ->
          :ok
      end
    end

    test "Continue Watching reflects fresh in-memory position written via Progress.record/3" do
      on_exit_clear_table()
      ensure_progress_worker!()
      Progress.reset_for_test!()

      movie = create_standalone_movie(%{name: "Stale CW Movie"})
      record_present(create_linked_file(%{movie_id: movie.id}))

      # Persist a stale 20% progress row on disk.
      persisted =
        create_watch_progress(%{
          movie_id: movie.id,
          position_seconds: 20.0,
          duration_seconds: 100.0
        })

      # Use the PlayableItem the persisted progress is bound to (the
      # `find_or_create_watch_progress_for_movie` writer resolves its
      # own canonical PI for the movie — Movie.position drives the
      # choice, which may differ from the file-linked PI).
      playable_item_id = persisted.playable_item_id

      # Write a fresh 80% position to in-memory state only. The
      # flush interval is 60s, so disk stays at 20% for the test.
      :ok = Progress.record(playable_item_id, 80.0, 100.0)

      # Sanity: ensure the in-memory row carries the fresh 80s position
      # before the cache refresh reads it. Without this, a Progress
      # API regression could mask the projection-side regression.
      hot = Progress.get(playable_item_id)
      assert hot.position_seconds == 80.0
      assert hot.playable_item_id == playable_item_id

      # Also check list_in_progress directly — bypasses the cache so
      # any DB-fallback path issues show up cleanly.
      [row] = MediaCentarr.Library.list_in_progress(limit: 5)
      assert row.entity_id == movie.id

      assert row.progress_pct == 80,
             "Library.list_in_progress should overlay in-memory progress (got #{row.progress_pct})"

      :ok = ContinueWatching.refresh_cache()

      [item] = Views.continue_watching(limit: 5)
      assert item.entity_id == movie.id

      # 80% from in-memory state, NOT 20% from disk. Pre-fix this was 20.
      assert item.progress_pct == 80
    end
  end

  describe "ContinueWatchingItem struct" do
    test "enforces entity_id and entity_name" do
      assert_raise ArgumentError, fn ->
        struct!(ContinueWatchingItem, %{})
      end
    end

    test "permits nil values for the optional fields" do
      item = %ContinueWatchingItem{entity_id: "id-1", entity_name: "Name"}

      assert item.last_episode_label == nil
      assert item.progress_pct == nil
      assert item.backdrop_url == nil
      assert item.logo_url == nil
      assert item.last_watched_at == nil
    end
  end
end
