defmodule MediaCentarr.ReleaseTracking.ExtractorTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ReleaseTracking.Extractor

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

  describe "extract_movie_release_dates/1" do
    test "extracts US theatrical and digital dates" do
      response = %{
        "title" => "Test Movie",
        "release_date" => "2026-05-10",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [
                %{
                  "release_date" => "2026-05-10T00:00:00.000Z",
                  "type" => 3,
                  "certification" => "PG-13"
                },
                %{
                  "release_date" => "2026-07-15T00:00:00.000Z",
                  "type" => 4,
                  "certification" => ""
                }
              ]
            }
          ]
        }
      }

      releases = Extractor.extract_movie_release_dates(response)
      assert length(releases) == 2

      theatrical = Enum.find(releases, &(&1.release_type == "theatrical"))
      assert theatrical.air_date == ~D[2026-05-10]
      assert theatrical.title == "Test Movie"

      digital = Enum.find(releases, &(&1.release_type == "digital"))
      assert digital.air_date == ~D[2026-07-15]
      assert digital.title == "Test Movie"
    end

    test "falls back to simple release_date when no detailed dates" do
      response = %{
        "title" => "Simple Movie",
        "release_date" => "2027-01-01",
        "release_dates" => %{"results" => []}
      }

      releases = Extractor.extract_movie_release_dates(response)
      assert length(releases) == 1
      assert hd(releases).air_date == ~D[2027-01-01]
      assert hd(releases).release_type == "theatrical"
    end

    test "falls back when no US entry exists" do
      response = %{
        "title" => "Foreign Movie",
        "release_date" => "2027-03-01",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "GB",
              "release_dates" => [%{"release_date" => "2027-02-01T00:00:00.000Z", "type" => 3}]
            }
          ]
        }
      }

      releases = Extractor.extract_movie_release_dates(response)
      assert length(releases) == 1
      assert hd(releases).air_date == ~D[2027-03-01]
    end

    test "handles nil release_dates" do
      response = %{"title" => "No Dates", "release_date" => nil, "release_dates" => nil}

      releases = Extractor.extract_movie_release_dates(response)
      assert length(releases) == 1
      assert hd(releases).air_date == nil
    end

    test "extracts only theatrical when no digital date" do
      response = %{
        "title" => "Theater Only",
        "release_date" => "2026-06-01",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [
                %{
                  "release_date" => "2026-06-01T00:00:00.000Z",
                  "type" => 3,
                  "certification" => "R"
                }
              ]
            }
          ]
        }
      }

      releases = Extractor.extract_movie_release_dates(response)
      assert length(releases) == 1
      assert hd(releases).release_type == "theatrical"
    end

    test "extracts US physical (type 5) release dates alongside theatrical and digital" do
      response = %{
        "title" => "Three-Stage Release",
        "release_date" => "2026-05-10",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [
                %{"release_date" => "2026-05-10T00:00:00.000Z", "type" => 3},
                %{"release_date" => "2026-07-15T00:00:00.000Z", "type" => 4},
                %{"release_date" => "2026-09-03T00:00:00.000Z", "type" => 5}
              ]
            }
          ]
        }
      }

      releases = Extractor.extract_movie_release_dates(response)
      assert length(releases) == 3

      physical = Enum.find(releases, &(&1.release_type == "physical"))
      assert physical.air_date == ~D[2026-09-03]
      assert physical.title == "Three-Stage Release"
    end
  end

  describe "extract_episodes_since/3" do
    test "returns episodes after the given season/episode" do
      season = %{
        "season_number" => 2,
        "episodes" => [
          %{"episode_number" => 10, "name" => "Ep 10", "air_date" => "2026-03-01"},
          %{"episode_number" => 11, "name" => "Ep 11", "air_date" => "2026-03-08"},
          %{"episode_number" => 12, "name" => "Ep 12", "air_date" => "2026-03-15"},
          %{"episode_number" => 13, "name" => "Ep 13", "air_date" => "2026-03-22"},
          %{"episode_number" => 14, "name" => "Ep 14", "air_date" => "2026-04-09"}
        ]
      }

      releases = Extractor.extract_episodes_since(season, 2, 12)
      assert length(releases) == 2
      assert Enum.map(releases, & &1.episode_number) == [13, 14]
    end

    test "returns all episodes when last is from a previous season" do
      season = %{
        "season_number" => 3,
        "episodes" => [
          %{"episode_number" => 1, "name" => "Premiere", "air_date" => "2026-06-01"},
          %{"episode_number" => 2, "name" => "Second", "air_date" => "2026-06-08"}
        ]
      }

      releases = Extractor.extract_episodes_since(season, 2, 12)
      assert length(releases) == 2
    end

    test "returns empty when all episodes are before or at last" do
      season = %{
        "season_number" => 2,
        "episodes" => [
          %{"episode_number" => 10, "name" => "Ep 10", "air_date" => "2026-03-01"},
          %{"episode_number" => 11, "name" => "Ep 11", "air_date" => "2026-03-08"},
          %{"episode_number" => 12, "name" => "Ep 12", "air_date" => "2026-03-15"}
        ]
      }

      releases = Extractor.extract_episodes_since(season, 2, 12)
      assert releases == []
    end

    test "handles nil air_date" do
      season = %{
        "season_number" => 2,
        "episodes" => [
          %{"episode_number" => 13, "name" => "Ep 13", "air_date" => nil}
        ]
      }

      releases = Extractor.extract_episodes_since(season, 2, 12)
      assert length(releases) == 1
      assert hd(releases).air_date == nil
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
