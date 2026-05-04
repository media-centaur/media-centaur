defmodule MediaCentarr.ReleaseTracking.ScannerTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TmdbStubs
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.ReleaseTracking.Scanner

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "scan/0" do
    test "tracks a TV series with upcoming episodes" do
      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "1396"})

      stub_routes([
        {"/tv/1396/season/6",
         %{
           "season_number" => 6,
           "episodes" => [
             %{"episode_number" => 1, "name" => "Return", "air_date" => "2026-06-15"}
           ]
         }},
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show",
           "status" => "Returning Series",
           "number_of_seasons" => 6,
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-06-15",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 1
      assert results.skipped == 0

      items = ReleaseTracking.list_watching_items()
      assert length(items) == 1
      assert hd(items).tmdb_id == 1396
      assert hd(items).library_entity_id == tv_series.id
    end

    test "tracks a TV series with gap episodes since last library episode" do
      tv_series = create_tv_series(%{name: "Sample Show B", tmdb_id: "2001"})

      # Create library episodes up to S2E12
      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 2, number_of_episodes: 12})

      for ep <- 1..12 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      stub_routes([
        {"/tv/2001/season/2",
         %{
           "season_number" => 2,
           "episodes" => [
             %{"episode_number" => 10, "name" => "Ep 10", "air_date" => "2026-03-01"},
             %{"episode_number" => 11, "name" => "Ep 11", "air_date" => "2026-03-08"},
             %{"episode_number" => 12, "name" => "Ep 12", "air_date" => "2026-03-15"},
             %{"episode_number" => 13, "name" => "Ep 13", "air_date" => "2026-03-22"},
             %{"episode_number" => 14, "name" => "Ep 14", "air_date" => "2027-04-09"}
           ]
         }},
        {"/tv/2001",
         %{
           "id" => 2001,
           "name" => "Sample Show B",
           "status" => "Returning Series",
           "number_of_seasons" => 2,
           "poster_path" => "/sample.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2027-04-09",
             "season_number" => 2,
             "episode_number" => 14,
             "name" => "Ep 14"
           }
         }}
      ])

      {:ok, results} = Scanner.scan()
      assert results.tracked == 1

      item = hd(ReleaseTracking.list_watching_items())
      assert item.last_library_season == 2
      assert item.last_library_episode == 12

      releases = ReleaseTracking.list_releases_for_item(item.id)

      assert length(releases) == 2
      ep13 = Enum.find(releases, &(&1.episode_number == 13))
      ep14 = Enum.find(releases, &(&1.episode_number == 14))
      assert ep13.released == true
      assert ep14.released == false
    end

    test "skips ended TV series with no upcoming episodes" do
      _tv_series = create_tv_series(%{name: "Sample Show C", tmdb_id: "1438"})

      stub_routes([
        {"/tv/1438",
         %{
           "id" => 1438,
           "name" => "Sample Show C",
           "status" => "Ended",
           "poster_path" => "/sample.jpg",
           "next_episode_to_air" => nil
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 0
      assert results.skipped == 1
    end

    test "tracks movie collection with unreleased parts" do
      _movie_series = create_movie_series(%{name: "Sample Movie Collection", tmdb_id: "263"})

      stub_routes([
        {"/collection/263",
         %{
           "id" => 263,
           "name" => "Sample Movie Collection",
           "poster_path" => "/sample.jpg",
           "parts" => [
             %{"id" => 155, "title" => "Sample Movie A", "release_date" => "2008-07-18"},
             %{
               "id" => 99_999,
               "title" => "Sample Movie B",
               "release_date" => "2027-07-01"
             }
           ]
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 1
      items = ReleaseTracking.list_watching_items()
      assert hd(items).media_type == :movie
    end

    test "is idempotent — skips already tracked items" do
      _tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "1396"})

      create_tracking_item(%{
        tmdb_id: 1396,
        media_type: :tv_series,
        name: "Sample Show"
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-06-15",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      {:ok, results} = Scanner.scan()
      assert results.skipped == 1
      assert results.tracked == 0
    end
  end
end
