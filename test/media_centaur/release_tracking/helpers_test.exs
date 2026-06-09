defmodule MediaCentaur.ReleaseTracking.HelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.Helpers

  describe "fetch_movie_releases/1" do
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

      releases = Helpers.fetch_movie_releases(response)

      theatrical = Enum.find(releases, &(Map.get(&1, :release_type) == "theatrical"))
      digital = Enum.find(releases, &(Map.get(&1, :release_type) == "digital"))

      assert theatrical.air_date == ~D[2026-06-23]
      assert theatrical.season_number == nil
      assert digital.air_date == ~D[2026-09-01]
    end

    test "falls back to a single theatrical release when no typed dates exist" do
      response = %{"title" => "Sample Film", "release_date" => "2026-06-23"}

      assert [release] = Helpers.fetch_movie_releases(response)
      assert release.release_type == "theatrical"
      assert release.air_date == ~D[2026-06-23]
    end
  end
end
