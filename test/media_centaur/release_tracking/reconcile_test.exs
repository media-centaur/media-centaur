defmodule MediaCentaur.ReleaseTracking.ReconcileTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbStubs

  # Adding to the watchlist promotes artwork on a context-owned task
  # (ADR-049), which needs both the TMDB client and the artwork cache
  # stubbed to stay offline. Each test that adds one drains the task
  # before it ends, so nothing outlives the sandbox.
  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()
    :ok
  end

  # ADR-065. The library reason is a default and evaporates; the watchlist
  # reason is an act and outlives it. These are the four cases the design
  # conversation turned on.

  defp tracked(attrs) do
    create_tracking_item(Map.merge(%{tmdb_id: 7001, media_type: :tv_series, name: "Sample Show"}, attrs))
  end

  describe "reconcile/2 — losing the library reason" do
    test "a series a person armed keeps tracking after the library drops it" do
      create_watchlist_item(%{tmdb_id: 7001, media_type: :tv_series})
      await_supervised_tasks()
      item = tracked(%{tracking_mode: :grab})

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      kept = ReleaseTracking.get_item(item.id)
      assert kept, "an armed title must survive losing the library"
      assert kept.tracking_mode == :grab, "and must keep the mode the person set"
    end

    test "a series only the app default was tracking stops" do
      item = tracked(%{tracking_mode: :global})

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      refute ReleaseTracking.get_item(item.id)
    end

    test "a series still owned keeps tracking" do
      container_id = Ecto.UUID.generate()

      item =
        tracked(%{
          tracking_mode: :global,
          library_container_type: :tv_series,
          library_container_id: container_id
        })

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      assert ReleaseTracking.get_item(item.id)
    end
  end

  describe "reconcile/2 — the durable disarm" do
    test "a deliberately disarmed title survives with no reason held" do
      item = tracked(%{tracking_mode: :none})

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      kept = ReleaseTracking.get_item(item.id)
      assert kept, "a disarm must never be lost — re-acquiring would silently re-arm"
      assert kept.tracking_mode == :none
    end
  end

  describe "reconcile/2 — de-listing" do
    test "removing an unowned armed title from the watchlist stops tracking" do
      create_watchlist_item(%{tmdb_id: 7001, media_type: :tv_series})
      await_supervised_tasks()
      item = tracked(%{tracking_mode: :watch})

      :ok = MediaCentaur.Discovery.remove_from_watchlist(7001, :tv_series)
      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      refute ReleaseTracking.get_item(item.id)
    end
  end

  describe "reconcile/2 — unknown titles" do
    test "is a no-op for a title that is not tracked" do
      assert :ok = ReleaseTracking.reconcile(999_123, :movie)
    end
  end
end
