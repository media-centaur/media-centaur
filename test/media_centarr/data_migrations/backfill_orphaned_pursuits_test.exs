defmodule MediaCentarr.DataMigrations.BackfillOrphanedPursuitsTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TestFactory

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarr.Acquisition.Pursuits.{Event, Pursuit}
  alias MediaCentarr.Repo
  alias MediaCentarr.Repo.DataMigrations.BackfillOrphanedPursuits

  describe "backfill/1" do
    test "creates a pursuit + pursuit_started event for an in-flight grab missing pursuit_id" do
      grab =
        create_grab(%{
          tmdb_id: "555",
          tmdb_type: "movie",
          title: "Sample Movie",
          year: 2020,
          status: "searching",
          origin: "auto"
        })

      assert grab.pursuit_id == nil

      BackfillOrphanedPursuits.backfill(Repo)

      reloaded = Repo.get!(Grab, grab.id)
      assert reloaded.pursuit_id != nil

      pursuit = Repo.get!(Pursuit, reloaded.pursuit_id)
      assert pursuit.state == "active"
      assert pursuit.origin == "auto"
      assert pursuit.tmdb_id == "555"
      assert pursuit.tmdb_type == "movie"
      assert pursuit.title == "Sample Movie"
      assert pursuit.year == 2020

      events = Repo.all(Event)
      assert [event] = Enum.filter(events, &(&1.pursuit_id == pursuit.id))
      assert event.kind == "pursuit_started"
      assert event.denormalized_pursuit_title == "Sample Movie"
      assert event.payload == %{"origin" => "auto"}
    end

    test "carries TV identifiers, attempt_count, and origin onto the pursuit" do
      grab =
        create_grab(%{
          tmdb_id: "999",
          tmdb_type: "tv",
          title: "Sample Show",
          season_number: 1,
          episode_number: 3,
          status: "snoozed",
          origin: "manual",
          attempt_count: 4
        })

      BackfillOrphanedPursuits.backfill(Repo)

      reloaded = Repo.get!(Grab, grab.id)
      pursuit = Repo.get!(Pursuit, reloaded.pursuit_id)

      assert pursuit.tmdb_type == "tv"
      assert pursuit.season_number == 1
      assert pursuit.episode_number == 3
      assert pursuit.origin == "manual"
      assert pursuit.attempt_count == 4
    end

    test "skips terminal grabs (grabbed/abandoned/cancelled) — synthetic close events would be misleading" do
      grabbed = create_grab(%{tmdb_id: "1", title: "A", status: "grabbed"})
      abandoned = create_grab(%{tmdb_id: "2", title: "B", status: "abandoned"})
      cancelled = create_grab(%{tmdb_id: "3", title: "C", status: "cancelled"})

      BackfillOrphanedPursuits.backfill(Repo)

      assert Repo.get!(Grab, grabbed.id).pursuit_id == nil
      assert Repo.get!(Grab, abandoned.id).pursuit_id == nil
      assert Repo.get!(Grab, cancelled.id).pursuit_id == nil
      assert Repo.aggregate(Pursuit, :count) == 0
    end

    test "leaves grabs with an existing pursuit_id alone" do
      pursuit = create_pursuit(%{title: "Existing"})

      grab =
        create_grab(%{
          tmdb_id: "777",
          title: "Existing",
          status: "searching",
          pursuit_id: pursuit.id
        })

      BackfillOrphanedPursuits.backfill(Repo)

      reloaded = Repo.get!(Grab, grab.id)
      assert reloaded.pursuit_id == pursuit.id
      assert Repo.aggregate(Pursuit, :count) == 1
    end

    test "is idempotent — re-running does not duplicate pursuits" do
      create_grab(%{tmdb_id: "111", title: "Re-run target", status: "searching"})

      BackfillOrphanedPursuits.backfill(Repo)
      first_pursuit_count = Repo.aggregate(Pursuit, :count)
      first_event_count = Repo.aggregate(Event, :count)

      BackfillOrphanedPursuits.backfill(Repo)

      assert Repo.aggregate(Pursuit, :count) == first_pursuit_count
      assert Repo.aggregate(Event, :count) == first_event_count
    end

    test "no-op when there are no orphaned in-flight grabs" do
      BackfillOrphanedPursuits.backfill(Repo)

      assert Repo.aggregate(Pursuit, :count) == 0
      assert Repo.aggregate(Event, :count) == 0
    end
  end
end
