defmodule MediaCentaur.Acquisition.Plans.CommitPlanTest do
  @moduledoc """
  `CommitPlan` is the seam nothing grabs before: it turns a ready plan into
  one composite pursuit and lands each grab as an `acquired` target. The
  approve→grab path is covered end to end in `PlansTest`; this file pins
  what the landed target carries.
  """
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Pursuits.Units
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Repo

  @info_hash String.duplicate("a", 40)

  setup do
    # Configured *and* tested green: a plan run holds while Prowlarr is
    # unconfigured, so a half-configured fixture would snooze instead.
    :ok = MediaCentaur.ProwlarrStubs.mark_ready!()

    Req.Test.stub(:prowlarr, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/v1/indexer"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/indexerstatus"} ->
          Req.Test.json(conn, [])

        {"GET", "/api/v1/search"} ->
          Req.Test.json(conn, [
            %{
              "title" => "Sample.Movie.2010.1080p.BluRay.x264",
              "guid" => "movie-hd",
              "indexerId" => 1,
              "indexer" => "indexer-a",
              "seeders" => 40,
              "size" => 4_000_000_000,
              "infoHash" => @info_hash,
              "protocol" => "torrent"
            }
          ])

        _other ->
          Req.Test.json(conn, %{})
      end
    end)

    :ok
  end

  # Regression: approval grabbed each release at Prowlarr before it
  # recorded anything and stamped the plan last, in whatever process called
  # it — a crash midway left a pursuit and some grabs behind a plan still
  # `ready`, which its own overlap check then refused to approve again.
  test "approval records the pursuit, a grabbing target per release and the commit; the grab is owed" do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2010})
    MediaCentaur.JobRuns.run_enqueued_jobs()
    {:ok, plan} = Plans.fetch(plan.id)

    {{:ok, committed}, inserts} = MediaCentaur.JobRuns.capture_inserts(fn -> Plans.approve(plan) end)

    assert committed.status == "committed"
    assert [unit] = Units.for_pursuit(committed.pursuit_id)
    target = Repo.get!(Target, unit.current_target_id)
    assert target.status == "grabbing"
    assert target.prowlarr_guid == "movie-hd"

    assert [%{in_transaction?: true, args: %{"target_id" => target_id}}] =
             Enum.filter(inserts, &(&1.worker == "MediaCentaur.Acquisition.Jobs.GrabTarget"))

    assert target_id == target.id
  end

  test "a movie approve lands the target with the release's infohash and quality" do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2010})
    MediaCentaur.JobRuns.run_enqueued_jobs()
    {:ok, plan} = Plans.fetch(plan.id)
    assert plan.status == "ready"

    assert {:ok, committed} = Plans.approve(plan)
    MediaCentaur.JobRuns.run_enqueued_jobs()

    assert [unit] = Units.for_pursuit(committed.pursuit_id)
    target = Repo.get!(Target, unit.current_target_id)

    assert target.status == "acquired"
    assert target.prowlarr_guid == "movie-hd"
    assert target.torrent_hash == @info_hash
    assert target.quality == "1080p"
  end
end
