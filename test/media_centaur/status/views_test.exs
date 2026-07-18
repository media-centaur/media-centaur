defmodule MediaCentaur.Status.ViewsTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Status
  alias MediaCentaur.Status.LibraryOverview
  alias MediaCentaur.Status.Views
  alias MediaCentaur.Status.Views.StorageSnapshot
  alias MediaCentaur.Topics

  describe "overview projection" do
    test "refresh_cache writes a snapshot readable via Views.overview/0" do
      create_movie(%{name: "Sample Projection Movie"})

      assert :ok = Views.Overview.refresh_cache()

      assert %LibraryOverview{} = overview = Views.overview()
      assert overview.movie_count == 1
    end

    test "read falls back to a live build when the projection table is absent" do
      create_movie(%{name: "Sample Fallback Movie"})

      live = Status.fetch_overview()
      read = Views.overview()

      assert %LibraryOverview{} = read
      assert read.movie_count == live.movie_count
      assert read.show_count == live.show_count
    end

    test "refresh_cache broadcasts the derived-topic update" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.status_views())

      assert :ok = Views.Overview.refresh_cache()

      assert_receive {:status_view_updated, :overview}
    end

    test "library entity changes are relevant, unrelated messages are not" do
      assert Views.Overview.relevant?({:entities_changed, %{}})
      refute Views.Overview.relevant?(:unrelated_noise)
    end
  end

  describe "storage projection" do
    test "refresh_cache writes a snapshot readable via Views.storage/0" do
      assert :ok = Views.Storage.refresh_cache()

      assert %StorageSnapshot{} = snapshot = Views.storage()
      assert is_list(snapshot.drives)
      assert is_list(snapshot.dir_health)
      assert is_map(snapshot.at_risk)
      assert %DateTime{} = snapshot.measured_at
    end

    test "read falls back to a live measurement when the table is absent" do
      assert %StorageSnapshot{} = snapshot = Views.storage()
      assert is_list(snapshot.drives)
    end

    test "dir_health covers every configured media dir" do
      # Test env configures no media dirs (ADR-016), so health is empty —
      # the shape contract is what matters here.
      assert :ok = Views.Storage.refresh_cache()
      assert Views.storage().dir_health == []
    end

    test "refresh_cache broadcasts the derived-topic update" do
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.status_views())

      assert :ok = Views.Storage.refresh_cache()

      assert_receive {:status_view_updated, :storage}
    end

    test "availability and media-dir config changes are relevant" do
      assert Views.Storage.relevant?({:availability_changed, "/mnt/media", :unavailable})
      assert Views.Storage.relevant?({:config_updated, :media_dirs, []})
      refute Views.Storage.relevant?({:config_updated, :recent_changes_days, 5})
      refute Views.Storage.relevant?(:unrelated_noise)
    end
  end

  describe "subscribe/0" do
    test "subscribes the caller to status:views" do
      assert :ok = Views.subscribe()

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        Topics.status_views(),
        {:status_view_updated, :overview}
      )

      assert_receive {:status_view_updated, :overview}
    end
  end
end
