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
    config = :persistent_term.get({MediaCentaur.Settings.Config, :config})

    :persistent_term.put(
      {MediaCentaur.Settings.Config, :config},
      config
      |> Map.put(:prowlarr_url, "http://prowlarr.test")
      |> Map.put(:prowlarr_api_key, MediaCentaur.Secret.wrap("test-key"))
    )

    on_exit(fn -> :persistent_term.put({MediaCentaur.Settings.Config, :config}, config) end)

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

  test "a movie approve lands the target with the release's infohash and quality" do
    {:ok, plan} = Plans.create_movie_plan(%{tmdb_id: "777", title: "Sample Movie", year: 2010})
    {:ok, plan} = Plans.fetch(plan.id)
    assert plan.status == "ready"

    assert {:ok, committed} = Plans.approve(plan)

    assert [unit] = Units.for_pursuit(committed.pursuit_id)
    target = Repo.get!(Target, unit.current_target_id)

    assert target.status == "acquired"
    assert target.prowlarr_guid == "movie-hd"
    assert target.torrent_hash == @info_hash
    assert target.quality == "1080p"
  end
end
