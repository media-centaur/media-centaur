defmodule MediaCentaur.Acquisition.TargetingTest do
  use MediaCentaur.DataCase, async: false

  import MediaCentaur.TestFactory

  alias MediaCentaur.Acquisition.Targeting
  alias MediaCentaur.TmdbStubs

  setup do
    TmdbStubs.setup_tmdb_client()
    :ok
  end

  defp stub_sample_show, do: TmdbStubs.stub_series_universe_for_targeting()

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

    test "carries the show's origin countries for remake disambiguation" do
      stub_sample_show()

      assert {:ok, selection} = Targeting.series_selection("246810")
      assert selection.origin_country == ["US"]
    end

    test "carries the series poster path for the picker header" do
      stub_sample_show()

      assert {:ok, selection} = Targeting.series_selection("246810")

      # tv_detail fixture default — flows through untouched.
      assert selection.poster_path == "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg"
    end

    test "carries the series backdrop and English-first logo for the plan modal's shell" do
      TmdbStubs.stub_routes([
        {"/tv/246810/season/1",
         TmdbStubs.season_detail(%{
           "season_number" => 1,
           "episodes" => [
             %{"episode_number" => 1, "name" => "Pilot", "air_date" => "2020-01-01"}
           ]
         })},
        {"/tv/246810",
         TmdbStubs.tv_detail(%{
           "id" => 246_810,
           "name" => "Sample Show",
           "backdrop_path" => "/sample-backdrop.jpg",
           "images" => %{
             "logos" => [
               %{"iso_639_1" => "de", "file_path" => "/logo-de.png"},
               %{"iso_639_1" => "en", "file_path" => "/logo-en.png"}
             ]
           },
           "seasons" => [%{"season_number" => 1, "episode_count" => 1}]
         })}
      ])

      assert {:ok, selection} = Targeting.series_selection("246810")

      assert selection.backdrop_path == "/sample-backdrop.jpg"
      # English logo wins over list order — same pick the import mapper makes.
      assert selection.logo_path == "/logo-en.png"
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

    test "aired_counts/1 — per-season aired episode totals (the pack-fit denominator)" do
      stub_sample_show()

      {:ok, selection} = Targeting.series_selection("246810")

      # Season 1: both aired. Season 2: one aired, one far-future — the
      # unaired episode isn't in any pack, so it isn't counted.
      assert Targeting.aired_counts(selection) == %{"1" => 2, "2" => 1}
    end

    test "propagates TMDB errors" do
      TmdbStubs.stub_tmdb_error("/tv/999999", 404)

      assert {:error, _} = Targeting.series_selection("999999")
    end
  end

  describe "per-unit tracked subtraction (ADR-056)" do
    defp track_with_want(mode) do
      item =
        create_tracking_item(%{tmdb_id: 246_810, media_type: :tv_series, name: "Sample Show"})

      {:ok, item} = MediaCentaur.ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: mode})

      create_tracking_release(%{
        item_id: item.id,
        season_number: 2,
        episode_number: 1,
        air_date: ~D[2021-01-01],
        released: true
      })

      :ok = MediaCentaur.ReleaseTracking.sync_wants(item)
      item
    end

    test "an open want marks its episode tracked and leaves the defaults" do
      stub_sample_show()
      track_with_want("all_releases")

      {:ok, selection} = Targeting.series_selection("246810")

      tracked_episode =
        for season <- selection.seasons,
            episode <- season.episodes,
            episode.tracked?,
            do: {episode.season_number, episode.episode_number}

      assert tracked_episode == [{2, 1}]

      # Defaults subtract tracked wants — shown in the picker, not
      # pre-chosen (the cadence is already on it).
      assert Targeting.default_units(selection) == [{1, 1}, {1, 2}]
    end

    test "mode off means no subtraction — media search is the expected path" do
      stub_sample_show()
      track_with_want("off")

      {:ok, selection} = Targeting.series_selection("246810")

      refute Enum.any?(
               for(season <- selection.seasons, episode <- season.episodes, do: episode),
               & &1.tracked?
             )

      assert {2, 1} in Targeting.default_units(selection)
    end
  end
end
