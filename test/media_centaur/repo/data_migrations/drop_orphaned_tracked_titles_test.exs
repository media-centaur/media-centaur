defmodule MediaCentaur.Repo.DataMigrations.DropOrphanedTrackedTitlesTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.Repo
  alias MediaCentaur.Repo.DataMigrations.DropOrphanedTrackedTitles
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()
    :ok
  end

  describe "sweep/1" do
    test "deletes a tracked title left with no reason" do
      item = create_tracking_item(%{tmdb_id: 8101, media_type: :tv_series, name: "Sample Show"})

      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)

      refute ReleaseTracking.get_item(item.id)
    end

    test "keeps a title still linked to a library container" do
      item =
        create_tracking_item(%{
          tmdb_id: 8102,
          media_type: :tv_series,
          name: "Sample Show",
          library_container_type: :tv_series,
          library_container_id: Ecto.UUID.generate()
        })

      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)

      assert ReleaseTracking.get_item(item.id)
    end

    test "keeps a title on the watchlist" do
      create_watchlist_item(%{tmdb_id: 8103, media_type: :tv_series})
      await_supervised_tasks()
      item = create_tracking_item(%{tmdb_id: 8103, media_type: :tv_series, name: "Sample Show"})

      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)

      assert ReleaseTracking.get_item(item.id)
    end

    test "keeps a deliberately disarmed title — deleting one would silently re-arm it" do
      item = create_tracking_item(%{tmdb_id: 8104, media_type: :tv_series, name: "Sample Show"})
      {:ok, _} = ReleaseTracking.disarm(item)

      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)

      kept = ReleaseTracking.get_item(item.id)
      assert kept
      assert kept.tracking_mode == :none
    end

    test "matches on media_type too — a watchlisted movie does not rescue a series" do
      create_watchlist_item(%{tmdb_id: 8105, media_type: :movie})
      await_supervised_tasks()
      series = create_tracking_item(%{tmdb_id: 8105, media_type: :tv_series, name: "Sample Show"})

      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)

      refute ReleaseTracking.get_item(series.id)
    end

    test "is idempotent" do
      item = create_tracking_item(%{tmdb_id: 8106, media_type: :tv_series, name: "Sample Show"})

      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)
      assert :ok = DropOrphanedTrackedTitles.sweep(Repo)

      refute ReleaseTracking.get_item(item.id)
    end
  end
end
