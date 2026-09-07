defmodule MediaCentaur.ReleaseTracking.ReconcileTest do
  @moduledoc """
  `reconcile/2` is the *other* direction from `set_rung/3`: the library
  moving underneath a rung nobody touched. It only ever drops, so it can
  run from the library listener without racing a person's act.

  The rule it applies is the whole of the derivation: a tracked title
  exists while the person follows the title and there is still a future
  to follow.
  """
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TaskAwaits, only: [await_supervised_tasks: 0]
  import MediaCentaur.TestFactory

  alias MediaCentaur.Discovery
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TmdbStubs

  # Putting a title on the ladder promotes artwork on a context-owned task
  # (ADR-049), which needs both the TMDB client and the artwork cache
  # stubbed to stay offline. Each test that writes one drains the task
  # before it ends, so nothing outlives the sandbox.
  setup do
    TmdbStubs.setup_tmdb_client()
    TmdbStubs.setup_artwork_cache()
    :ok
  end

  # `rung: nil` on purpose: these tests write the intent themselves (or
  # deliberately write none), because the rung is the thing under test.
  defp tracked(attrs \\ %{}) do
    create_tracking_item(
      Map.merge(%{tmdb_id: 7001, media_type: :tv_series, name: "Sample Show", rung: nil}, attrs)
    )
  end

  describe "reconcile/2 — the rung decides" do
    test "a series the person follows keeps its tracked title" do
      create_title_intent(%{tmdb_id: 7001, media_type: :tv_series, rung: :grab})
      await_supervised_tasks()
      item = tracked()

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      assert ReleaseTracking.get_item(item.id)
    end

    test "a series the person only listed does not" do
      create_title_intent(%{tmdb_id: 7001, media_type: :tv_series, rung: :list})
      await_supervised_tasks()
      item = tracked()

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      refute ReleaseTracking.get_item(item.id),
             "List keeps no calendar, so it derives no tracked title"
    end

    test "a series with no record at all does not — nobody asked for it" do
      item = tracked()

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      refute ReleaseTracking.get_item(item.id)
    end

    test "a library container is not a reason on its own" do
      item =
        tracked(%{
          library_container_type: :tv_series,
          library_container_id: Ecto.UUID.generate()
        })

      :ok = ReleaseTracking.reconcile(7001, :tv_series)

      refute ReleaseTracking.get_item(item.id),
             "owning a series is a fact about the library, not a request to follow it"
    end
  end

  describe "reconcile/2 — a film you own is complete" do
    test "the tracked title goes even at a grabbing rung" do
      movie = create_standalone_movie(%{name: "Owned Film"})
      create_external_id(%{movie_id: movie.id, source: "tmdb", external_id: "7002"})
      create_linked_file(%{movie_id: movie.id})

      create_title_intent(%{tmdb_id: 7002, media_type: :movie, rung: :grab, name: "Owned Film"})
      await_supervised_tasks()

      item =
        create_tracking_item(%{tmdb_id: 7002, media_type: :movie, name: "Owned Film", rung: nil})

      :ok = ReleaseTracking.reconcile(7002, :movie)

      refute ReleaseTracking.get_item(item.id)
      assert Discovery.rung(7002, :movie) == :grab, "the rung is the person's; nothing lowers it"
    end
  end

  describe "reconcile/2 — unknown titles" do
    test "is a no-op for a title that is not tracked" do
      assert :ok = ReleaseTracking.reconcile(999_123, :movie)
    end
  end
end
