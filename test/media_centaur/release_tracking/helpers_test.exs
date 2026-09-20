defmodule MediaCentaur.ReleaseTracking.HelpersTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.ReleaseTracking.Calendar
  alias MediaCentaur.ReleaseTracking.Helpers

  describe "parse_tmdb_id/1" do
    test "passes integers through" do
      assert Helpers.parse_tmdb_id(550) == {:ok, 550}
    end

    test "parses well-formed string ids" do
      assert Helpers.parse_tmdb_id("550") == {:ok, 550}
    end

    test "rejects malformed ids instead of crashing" do
      assert Helpers.parse_tmdb_id("550-collection") == :error
      assert Helpers.parse_tmdb_id("not-a-number") == :error
      assert Helpers.parse_tmdb_id("") == :error
    end
  end

  describe "Calendar.movie_releases/1" do
    # The initial-track path (Extractor.extract_movie_release_dates) keeps
    # release_type; the refresh path (this function) must keep it too, or the
    # same movie's releases churn between refreshes (the keys stop matching).
    test "preserves release_type from typed US release dates" do
      response = %{
        "title" => "Sample Film",
        "release_dates" => %{
          "results" => [
            %{
              "iso_3166_1" => "US",
              "release_dates" => [
                %{"type" => 3, "release_date" => "2026-06-23T00:00:00.000Z"},
                %{"type" => 4, "release_date" => "2026-09-01T00:00:00.000Z"}
              ]
            }
          ]
        }
      }

      releases = Calendar.movie_releases(response)

      theatrical = Enum.find(releases, &(Map.get(&1, :release_type) == "theatrical"))
      digital = Enum.find(releases, &(Map.get(&1, :release_type) == "digital"))

      assert theatrical.air_date == ~D[2026-06-23]
      assert theatrical.season_number == nil
      assert digital.air_date == ~D[2026-09-01]
    end

    test "falls back to a single theatrical release when no typed dates exist" do
      response = %{"title" => "Sample Film", "release_date" => "2026-06-23"}

      assert [release] = Calendar.movie_releases(response)
      assert release.release_type == "theatrical"
      assert release.air_date == ~D[2026-06-23]
    end

    test "stamps every row with the movie's own tmdb id (want-ledger unit identity)" do
      response = %{"id" => 603, "title" => "Sample Film", "release_date" => "2026-06-23"}

      assert [release] = Calendar.movie_releases(response)
      assert release.part_tmdb_id == 603
    end
  end
end
