defmodule MediaCentaur.Acquisition.TargetingTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  defp stub_sample_show do
    # Season routes first — `stub_routes` matches by path substring, and
    # "/tv/246810" would otherwise swallow the season paths.
    TmdbStubs.stub_routes([
      {"/tv/246810/season/1",
       TmdbStubs.season_detail(%{
         "season_number" => 1,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"},
           %{"episode_number" => 2, "name" => "Second", "air_date" => "2020-01-08"}
         ]
       })},
      {"/tv/246810/season/2",
       TmdbStubs.season_detail(%{
         "season_number" => 2,
         "episodes" => [
           %{"episode_number" => 1, "name" => "Return", "air_date" => "2021-01-01"},
           # Far future — not aired.
           %{"episode_number" => 2, "name" => "Finale", "air_date" => "2199-01-01"}
         ]
       })},
      {"/tv/246810",
       TmdbStubs.tv_detail(%{
         "id" => 246_810,
         "name" => "Sample Show",
         "seasons" => [
           %{"season_number" => 0, "episode_count" => 1},
           %{"season_number" => 1, "episode_count" => 2},
           %{"season_number" => 2, "episode_count" => 2}
         ]
       })}
    ])
  end

  describe "series_selection/1" do
    test "enumerates aired units per season, skipping specials" do
      stub_sample_show()

      assert {:ok, selection} = Targeting.series_selection("246810")

      assert selection.tmdb_id == "246810"
      assert selection.title == "Sample Show"
      refute selection.tracked?

      # Season 0 (specials) is excluded.
      assert Enum.map(selection.seasons, & &1.season_number) == [1, 2]

      [season_one, season_two] = selection.seasons
      assert Enum.map(season_one.episodes, & &1.episode_number) == [1, 2]
      assert Enum.all?(season_one.episodes, & &1.aired?)

      [aired, unaired] = season_two.episodes
      assert aired.aired?
      refute unaired.aired?
    end

    test "marks library-present units (subtractions shown, not silent)" do
      stub_sample_show()

      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "246810"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        content_url: "/library/Sample.Show.S01E01.mkv"
      })

      assert {:ok, selection} = Targeting.series_selection("246810")

      [season_one, _season_two] = selection.seasons
      [first, second] = season_one.episodes
      assert first.in_library?
      refute second.in_library?
    end

    test "flags a series the release tracker already covers" do
      stub_sample_show()

      {:ok, _item} =
        MediaCentaur.ReleaseTracking.track_item(%{
          tmdb_id: 246_810,
          media_type: "tv_series",
          name: "Sample Show"
        })

      assert {:ok, selection} = Targeting.series_selection("246810")
      assert selection.tracked?
    end

    test "default_units/1 — everything aired, minus what the library has" do
      stub_sample_show()

      tv_series = create_tv_series(%{name: "Sample Show", tmdb_id: "246810"})
      season = create_season(%{tv_series_id: tv_series.id, season_number: 1})

      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        content_url: "/library/Sample.Show.S01E01.mkv"
      })

      {:ok, selection} = Targeting.series_selection("246810")

      assert Targeting.default_units(selection) == [{1, 2}, {2, 1}]
    end

    test "propagates TMDB errors" do
      TmdbStubs.stub_tmdb_error("/tv/999999", 404)

      assert {:error, _} = Targeting.series_selection("999999")
    end
  end
end
