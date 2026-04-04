defmodule MediaCentaur.ReleaseTracking.ExtractorTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.Extractor

  describe "extract_tv_status/1" do
    test "maps Returning Series" do
      assert Extractor.extract_tv_status(%{"status" => "Returning Series"}) == :returning
    end

    test "maps Ended" do
      assert Extractor.extract_tv_status(%{"status" => "Ended"}) == :ended
    end

    test "maps Canceled" do
      assert Extractor.extract_tv_status(%{"status" => "Canceled"}) == :canceled
    end

    test "maps In Production" do
      assert Extractor.extract_tv_status(%{"status" => "In Production"}) == :in_production
    end

    test "maps Planned" do
      assert Extractor.extract_tv_status(%{"status" => "Planned"}) == :planned
    end

    test "returns :unknown for missing status" do
      assert Extractor.extract_tv_status(%{}) == :unknown
    end
  end

  describe "extract_tv_releases/1" do
    test "extracts next_episode_to_air" do
      response = %{
        "next_episode_to_air" => %{
          "air_date" => "2026-06-15",
          "season_number" => 3,
          "episode_number" => 1,
          "name" => "The Return"
        },
        "status" => "Returning Series"
      }

      assert [release] = Extractor.extract_tv_releases(response)
      assert release.air_date == ~D[2026-06-15]
      assert release.season_number == 3
      assert release.episode_number == 1
      assert release.title == "The Return"
    end

    test "returns empty list for ended show with no next episode" do
      response = %{
        "next_episode_to_air" => nil,
        "status" => "Ended"
      }

      assert [] = Extractor.extract_tv_releases(response)
    end

    test "handles nil air_date in next_episode_to_air" do
      response = %{
        "next_episode_to_air" => %{
          "air_date" => nil,
          "season_number" => 2,
          "episode_number" => 1,
          "name" => "TBA"
        },
        "status" => "Returning Series"
      }

      assert [release] = Extractor.extract_tv_releases(response)
      assert release.air_date == nil
      assert release.season_number == 2
    end

    test "handles missing next_episode_to_air key" do
      response = %{"status" => "Returning Series"}
      assert [] = Extractor.extract_tv_releases(response)
    end
  end

  describe "extract_season_releases/1" do
    test "extracts future episodes from season data" do
      today = Date.utc_today()
      future = Date.to_iso8601(Date.add(today, 7))
      past = Date.to_iso8601(Date.add(today, -7))

      season = %{
        "season_number" => 2,
        "episodes" => [
          %{"episode_number" => 1, "name" => "Past Ep", "air_date" => past},
          %{"episode_number" => 2, "name" => "Future Ep", "air_date" => future},
          %{"episode_number" => 3, "name" => "No Date", "air_date" => nil}
        ]
      }

      releases = Extractor.extract_season_releases(season)
      assert length(releases) == 2

      future_ep = Enum.find(releases, &(&1.episode_number == 2))
      assert future_ep.title == "Future Ep"
      assert future_ep.season_number == 2

      no_date = Enum.find(releases, &(&1.episode_number == 3))
      assert no_date.air_date == nil
    end
  end

  describe "extract_movie_status/1" do
    test "maps Released" do
      assert Extractor.extract_movie_status(%{"status" => "Released"}) == :released
    end

    test "maps In Production" do
      assert Extractor.extract_movie_status(%{"status" => "In Production"}) == :in_production
    end

    test "maps Post Production" do
      assert Extractor.extract_movie_status(%{"status" => "Post Production"}) == :post_production
    end

    test "maps Planned" do
      assert Extractor.extract_movie_status(%{"status" => "Planned"}) == :planned
    end

    test "maps Rumored" do
      assert Extractor.extract_movie_status(%{"status" => "Rumored"}) == :rumored
    end

    test "maps Canceled" do
      assert Extractor.extract_movie_status(%{"status" => "Canceled"}) == :canceled
    end
  end

  describe "extract_collection_releases/1" do
    test "extracts unreleased movies from collection parts" do
      collection = %{
        "parts" => [
          %{"id" => 1, "title" => "Movie 1", "release_date" => "2020-01-01"},
          %{"id" => 2, "title" => "Movie 2", "release_date" => "2027-12-25"},
          %{"id" => 3, "title" => "Movie 3", "release_date" => ""}
        ]
      }

      releases = Extractor.extract_collection_releases(collection)
      assert length(releases) == 2

      movie2 = Enum.find(releases, &(&1.title == "Movie 2"))
      assert movie2.air_date == ~D[2027-12-25]
      assert movie2.tmdb_id == 2

      movie3 = Enum.find(releases, &(&1.title == "Movie 3"))
      assert movie3.air_date == nil
    end

    test "returns empty for all-released collection" do
      collection = %{
        "parts" => [
          %{"id" => 1, "title" => "Movie 1", "release_date" => "2020-01-01"}
        ]
      }

      assert [] = Extractor.extract_collection_releases(collection)
    end
  end

  describe "extract_poster_path/1" do
    test "returns poster_path from response" do
      assert Extractor.extract_poster_path(%{"poster_path" => "/abc.jpg"}) == "/abc.jpg"
    end

    test "returns nil when missing" do
      assert Extractor.extract_poster_path(%{}) == nil
    end
  end
end
