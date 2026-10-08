defmodule MediaCentaur.WatchHistory.Views.SummaryTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Topics
  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Views
  alias MediaCentaur.WatchHistory.Views.Summary
  alias MediaCentaur.WatchHistory.Views.SummaryData

  @cache_key {Summary, :data}

  describe "Cache behaviour — relevant?/1" do
    test "accepts watch-event creation" do
      assert Summary.relevant?({:watch_event_created, %{}})
    end

    test "accepts watch-event deletion" do
      assert Summary.relevant?({:watch_event_deleted, %{}})
    end

    test "rejects unrelated messages" do
      refute Summary.relevant?(:something_else)
      refute Summary.relevant?({:entities_changed, %{}})
      refute Summary.relevant?({:other, "payload"})
    end
  end

  describe "refresh_cache/0" do
    test "populates :persistent_term with one SummaryData per profile" do
      movie = create_standalone_movie(%{name: "Replayed"})
      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Replayed"})
      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Replayed"})

      assert :ok = Summary.refresh_cache()

      assert %{} = snapshot = :persistent_term.get(@cache_key)
      assert Map.keys(snapshot) == [owner_profile_id()]

      summary = Views.summary(owner_profile_id())

      assert %SummaryData{} = summary
      assert summary.stats.total_count == 2
      assert summary.rewatch_counts[:movie][movie.id] == 2
      assert is_map(summary.heatmap_cells_by_type)
      assert Map.has_key?(summary.heatmap_cells_by_type, nil)
      assert Map.has_key?(summary.heatmap_cells_by_type, :movie)
    end

    test "the snapshot is per profile; a profile with no events computes an empty summary" do
      movie = create_standalone_movie(%{name: "Replayed"})
      me = owner_profile_id()
      ana = create_profile(%{name: "Ana"}).id
      create_watch_event(%{profile_id: me, movie_id: movie.id, entity_type: :movie, title: "Replayed"})
      create_watch_event(%{profile_id: me, movie_id: movie.id, entity_type: :movie, title: "Replayed"})

      assert :ok = Summary.refresh_cache()
      assert Views.summary(me).stats.total_count == 2
      assert Views.summary(me).rewatch_counts[:movie][movie.id] == 2
      assert Views.summary(ana).stats.total_count == 0
      assert Views.summary(ana).rewatch_counts == %{movie: %{}, episode: %{}, video_object: %{}}
    end

    test "broadcasts {:watch_history_view_updated, :summary} after refresh" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.watch_history_views())

      movie = create_standalone_movie(%{name: "Broadcast"})
      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Broadcast"})

      assert :ok = Summary.refresh_cache()

      assert_receive {:watch_history_view_updated, :summary}
    end

    test "is idempotent — repeat calls replace the snapshot, no leak" do
      movie = create_standalone_movie(%{name: "Idempotent"})
      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Idempotent"})
      assert :ok = Summary.refresh_cache()
      assert Views.summary(owner_profile_id()).stats.total_count == 1

      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Idempotent"})
      assert :ok = Summary.refresh_cache()
      assert Views.summary(owner_profile_id()).stats.total_count == 2

      # Refresh without DB changes preserves the snapshot.
      assert :ok = Summary.refresh_cache()
      assert Views.summary(owner_profile_id()).stats.total_count == 2
    end
  end

  describe "Views.summary/1 — :persistent_term path vs DB fallback" do
    test "falls back to live DB queries when :persistent_term is unset" do
      movie = create_standalone_movie(%{name: "Cold"})
      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Cold"})

      assert :persistent_term.get(@cache_key, :__unset) == :__unset

      summary = Views.summary(owner_profile_id())

      assert %SummaryData{} = summary
      assert summary.stats.total_count == 1
      assert summary.rewatch_counts[:movie][movie.id] == 1
    end
  end

  describe "equivalence with the legacy live read paths" do
    test "cached summary matches the per-call WatchHistory reads for the same DB state" do
      movie = create_standalone_movie(%{name: "Equiv"})
      create_watch_event(%{movie_id: movie.id, entity_type: :movie, title: "Equiv"})

      :ok = Summary.refresh_cache()
      cached = Views.summary(owner_profile_id())

      legacy_stats = WatchHistory.stats(owner_profile_id())
      legacy_heatmap = WatchHistory.heatmap_cells_by_type(owner_profile_id())

      assert cached.stats.total_count == legacy_stats.total_count
      assert cached.stats.total_seconds == legacy_stats.total_seconds
      assert cached.stats.streak == legacy_stats.streak
      assert Map.keys(cached.heatmap_cells_by_type) == Map.keys(legacy_heatmap)

      assert cached.rewatch_counts == %{
               movie: WatchHistory.rewatch_count_map(owner_profile_id(), :movie),
               episode: WatchHistory.rewatch_count_map(owner_profile_id(), :episode),
               video_object: WatchHistory.rewatch_count_map(owner_profile_id(), :video_object)
             }
    end
  end

  describe "SummaryData struct" do
    test "enforces stats, heatmap_cells_by_type, rewatch_counts" do
      assert_raise ArgumentError, fn -> struct!(SummaryData, %{}) end
    end
  end
end
