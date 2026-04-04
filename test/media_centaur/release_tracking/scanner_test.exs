defmodule MediaCentaur.ReleaseTracking.ScannerTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TmdbStubs
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Scanner

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "scan/0" do
    test "tracks a TV series with upcoming episodes" do
      tv_series = create_tv_series(%{name: "Sample Show Eight"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "1396"})

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
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

      assert results.tracked == 1
      assert results.skipped == 0

      items = ReleaseTracking.list_watching_items()
      assert length(items) == 1
      assert hd(items).tmdb_id == 1396
      assert hd(items).library_entity_id == tv_series.id
    end

    test "skips ended TV series with no upcoming episodes" do
      tv_series = create_tv_series(%{name: "Sample Show"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "1438"})

      stub_routes([
        {"/tv/1438",
         %{
           "id" => 1438,
           "name" => "Sample Show",
           "status" => "Ended",
           "poster_path" => "/wire.jpg",
           "next_episode_to_air" => nil
         }}
      ])

      {:ok, results} = Scanner.scan()

      assert results.tracked == 0
      assert results.skipped == 1
    end

    test "tracks movie collection with unreleased parts" do
      movie_series = create_movie_series(%{name: "Dark Knight Collection"})

      create_external_id(%{
        movie_series_id: movie_series.id,
        source: "tmdb_collection",
        external_id: "263"
      })

      stub_routes([
        {"/collection/263",
         %{
           "id" => 263,
           "name" => "Dark Knight Collection",
           "poster_path" => "/dk.jpg",
           "parts" => [
             %{"id" => 155, "title" => "The Shadowy Sentinel", "release_date" => "2008-07-18"},
             %{
               "id" => 99999,
               "title" => "The Shadowy Sentinel Returns",
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
      tv_series = create_tv_series(%{name: "Sample Show Eight"})
      create_external_id(%{tv_series_id: tv_series.id, source: "tmdb", external_id: "1396"})

      create_tracking_item(%{
        tmdb_id: 1396,
        media_type: :tv_series,
        name: "Sample Show Eight"
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show Eight",
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
