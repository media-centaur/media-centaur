defmodule MediaCentaur.Library.CompletenessTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Library.Completeness

  describe "incomplete_season_count/0" do
    test "counts a season holding an aired episode with no file" do
      series = create_tv_series(%{name: "Sample Show"})

      season =
        create_season(%{
          season_number: 1,
          tv_series_id: series.id,
          episode_list: [
            %{episode_number: 1, air_date: "2020-01-01"},
            %{episode_number: 2, air_date: "2020-01-08"}
          ]
        })

      create_episode(%{episode_number: 1, season_id: season.id})

      assert Completeness.incomplete_season_count() == 1
    end

    test "does not count a season whose listed episodes all have files" do
      series = create_tv_series(%{name: "Sample Show"})

      season =
        create_season(%{
          season_number: 1,
          tv_series_id: series.id,
          episode_list: [
            %{episode_number: 1, air_date: "2020-01-01"},
            %{episode_number: 2, air_date: "2020-01-08"}
          ]
        })

      create_episode(%{episode_number: 1, season_id: season.id})
      create_episode(%{episode_number: 2, season_id: season.id})

      assert Completeness.incomplete_season_count() == 0
    end

    test "does not count a season whose only absent episodes have not aired" do
      series = create_tv_series(%{name: "Sample Show"})
      future = Date.utc_today() |> Date.add(30) |> Date.to_iso8601()

      season =
        create_season(%{
          season_number: 1,
          tv_series_id: series.id,
          episode_list: [
            %{episode_number: 1, air_date: "2020-01-01"},
            %{episode_number: 2, air_date: future}
          ]
        })

      create_episode(%{episode_number: 1, season_id: season.id})

      assert Completeness.incomplete_season_count() == 0
    end

    test "an undated listed episode with no file counts as a gap" do
      series = create_tv_series(%{name: "Sample Show"})

      create_season(%{
        season_number: 1,
        tv_series_id: series.id,
        episode_list: [%{episode_number: 1, air_date: nil}]
      })

      assert Completeness.incomplete_season_count() == 1
    end

    test "a season with an empty episode list never counts" do
      series = create_tv_series(%{name: "Sample Show"})
      create_season(%{season_number: 1, tv_series_id: series.id, episode_list: []})

      assert Completeness.incomplete_season_count() == 0
    end

    test "each short season of one series counts separately" do
      series = create_tv_series(%{name: "Sample Show"})

      for number <- [1, 2] do
        create_season(%{
          season_number: number,
          tv_series_id: series.id,
          episode_list: [%{episode_number: 1, air_date: "2020-01-01"}]
        })
      end

      assert Completeness.incomplete_season_count() == 2
    end
  end

  describe "missing_metadata_count/0" do
    test "counts library containers with no TMDB external id" do
      create_movie(%{name: "Unmatched Movie"})

      assert Completeness.missing_metadata_count() == 1
    end

    test "excludes containers that have a TMDB external id" do
      create_movie(%{name: "Matched Movie", tmdb_id: "12345"})

      assert Completeness.missing_metadata_count() == 0
    end

    test "uses the collection source for movie series" do
      create_movie_series(%{name: "Unmatched Collection"})
      create_movie_series(%{name: "Matched Collection", tmdb_id: "999"})

      assert Completeness.missing_metadata_count() == 1
    end

    test "returns zero for an empty library" do
      assert Completeness.missing_metadata_count() == 0
    end
  end
end
