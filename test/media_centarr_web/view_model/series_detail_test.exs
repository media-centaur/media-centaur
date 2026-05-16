defmodule MediaCentarrWeb.ViewModel.SeriesDetailTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.Watcher.FilePresence
  alias MediaCentarrWeb.ViewModel.EpisodeListItem
  alias MediaCentarrWeb.ViewModel.SeasonView
  alias MediaCentarrWeb.ViewModel.SeriesDetail

  defp record_present(file), do: FilePresence.record_file(file.file_path, file.watch_dir)

  describe "build/4 — pure composition" do
    test "no releases: items mirror library episodes with gap-fill" do
      season = season_with_episodes(1, 5, [1, 2, 3, 5])
      tv = build_tv_series(%{seasons: [season]})

      view_model =
        SeriesDetail.build(
          %{
            entity: tv,
            progress: nil,
            progress_records: []
          },
          [],
          nil,
          nil
        )

      assert [%SeasonView{kind: :library, season_number: 1, items: items}] = view_model.seasons
      assert length(items) == 5

      assert [
               %EpisodeListItem.Library{},
               %EpisodeListItem.Library{},
               %EpisodeListItem.Library{},
               %EpisodeListItem.Missing{episode_number: 4},
               %EpisodeListItem.Library{}
             ] = items
    end

    test "release matching a Missing slot replaces it with Upcoming" do
      season = season_with_episodes(1, 5, [1, 2, 3])
      tv = build_tv_series(%{seasons: [season]})

      releases = [
        release_map(%{season_number: 1, episode_number: 4, released: false, title: "The Gap"}),
        release_map(%{season_number: 1, episode_number: 5, released: false, title: "The End"})
      ]

      view_model =
        SeriesDetail.build(
          %{entity: tv, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      [%SeasonView{items: items}] = view_model.seasons

      assert [
               %EpisodeListItem.Library{episode: %{episode_number: 1}},
               %EpisodeListItem.Library{episode: %{episode_number: 2}},
               %EpisodeListItem.Library{episode: %{episode_number: 3}},
               %EpisodeListItem.Upcoming{episode_number: 4, title: "The Gap", sub_status: :unaired},
               %EpisodeListItem.Upcoming{episode_number: 5, title: "The End"}
             ] = items
    end

    test "release beyond number_of_episodes extends the items list" do
      season = season_with_episodes(1, 3, [1, 2, 3])
      tv = build_tv_series(%{seasons: [season]})

      releases = [
        release_map(%{season_number: 1, episode_number: 4, released: false}),
        release_map(%{season_number: 1, episode_number: 5, released: false})
      ]

      view_model =
        SeriesDetail.build(
          %{entity: tv, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      [%SeasonView{items: items, total_count: total}] = view_model.seasons
      assert length(items) == 5
      # total_count tracks library size; the extra upcoming rows past
      # number_of_episodes don't inflate watched-against-X copy.
      assert total == 3

      assert [
               _,
               _,
               _,
               %EpisodeListItem.Upcoming{episode_number: 4},
               %EpisodeListItem.Upcoming{episode_number: 5}
             ] =
               items
    end

    test "release in a season not in library becomes a future-season bucket" do
      season1 = season_with_episodes(1, 3, [1, 2, 3])
      tv = build_tv_series(%{seasons: [season1]})

      releases = [
        release_map(%{season_number: 2, episode_number: 1, released: false, title: "S2 Premiere"}),
        release_map(%{season_number: 2, episode_number: 2, released: false})
      ]

      view_model =
        SeriesDetail.build(
          %{entity: tv, progress: nil, progress_records: []},
          releases,
          :watching,
          nil
        )

      assert [
               %SeasonView{kind: :library, season_number: 1},
               %SeasonView{kind: :future, season_number: 2, items: future_items, watched_count: nil}
             ] = view_model.seasons

      assert length(future_items) == 2
      assert Enum.all?(future_items, &match?(%EpisodeListItem.Upcoming{}, &1))
    end

    test "future-season items are sorted by episode_number regardless of input order" do
      tv = build_tv_series(%{seasons: []})

      releases = [
        release_map(%{season_number: 2, episode_number: 3}),
        release_map(%{season_number: 2, episode_number: 1}),
        release_map(%{season_number: 2, episode_number: 2})
      ]

      view_model =
        SeriesDetail.build(%{entity: tv, progress: nil, progress_records: []}, releases, :watching, nil)

      [%SeasonView{items: items}] = view_model.seasons
      assert Enum.map(items, & &1.episode_number) == [1, 2, 3]
    end

    test "aired-but-not-in-library release gets sub_status :aired_not_in_library" do
      tv = build_tv_series(%{seasons: []})

      releases = [
        release_map(%{
          season_number: 1,
          episode_number: 1,
          released: true,
          in_library: false,
          air_date: ~D[2026-04-01]
        })
      ]

      view_model =
        SeriesDetail.build(%{entity: tv, progress: nil, progress_records: []}, releases, :watching, nil)

      [%SeasonView{items: [item]}] = view_model.seasons

      assert %EpisodeListItem.Upcoming{sub_status: :aired_not_in_library, air_date: ~D[2026-04-01]} =
               item
    end

    test "watched_count and total_count reflect library state, not releases" do
      [ep1, ep2, ep3] = build_episodes([1, 2, 3])
      season = build_season(%{season_number: 1, number_of_episodes: 3, episodes: [ep1, ep2, ep3]})
      tv = build_tv_series(%{seasons: [season]})

      progress_records = [
        build_progress(%{episode_id: ep1.id, completed: true}),
        build_progress(%{episode_id: ep2.id, completed: false, position_seconds: 100.0})
      ]

      view_model =
        SeriesDetail.build(
          %{entity: tv, progress: nil, progress_records: progress_records},
          [],
          :watching,
          nil
        )

      [%SeasonView{watched_count: watched, total_count: total}] = view_model.seasons
      assert watched == 1
      assert total == 3
    end

    test "is_resume_target marks the matching library item from resume_target hint" do
      [ep1, ep2] = build_episodes([1, 2])
      season = build_season(%{season_number: 1, number_of_episodes: 2, episodes: [ep1, ep2]})
      tv = build_tv_series(%{seasons: [season]})

      resume_target = %{
        "action" => "resume",
        "seasonNumber" => 1,
        "episodeNumber" => 2
      }

      view_model =
        SeriesDetail.build(
          %{entity: tv, progress: nil, progress_records: []},
          [],
          :watching,
          resume_target
        )

      [%SeasonView{items: [item1, item2]}] = view_model.seasons
      assert %EpisodeListItem.Library{is_resume_target: false} = item1
      assert %EpisodeListItem.Library{is_resume_target: true} = item2
    end

    test "library_item.state reflects watch progress" do
      [ep1, ep2, ep3] = build_episodes([1, 2, 3])
      season = build_season(%{season_number: 1, number_of_episodes: 3, episodes: [ep1, ep2, ep3]})
      tv = build_tv_series(%{seasons: [season]})

      progress_records = [
        build_progress(%{episode_id: ep1.id, completed: true}),
        build_progress(%{
          episode_id: ep2.id,
          completed: false,
          position_seconds: 250.0,
          duration_seconds: 1500.0
        })
      ]

      view_model =
        SeriesDetail.build(
          %{entity: tv, progress: nil, progress_records: progress_records},
          [],
          :watching,
          nil
        )

      [%SeasonView{items: [item1, item2, item3]}] = view_model.seasons
      assert %EpisodeListItem.Library{state: :watched} = item1
      assert %EpisodeListItem.Library{state: :current} = item2
      assert %EpisodeListItem.Library{state: :unwatched} = item3
    end

    test "tracking_status field passes through unchanged" do
      tv = build_tv_series(%{seasons: []})

      view_model =
        SeriesDetail.build(%{entity: tv, progress: nil, progress_records: []}, [], :ignored, nil)

      assert view_model.tracking_status == :ignored

      view_model = SeriesDetail.build(%{entity: tv, progress: nil, progress_records: []}, [], nil, nil)
      assert view_model.tracking_status == nil
    end

    test "season with no episodes and zero number_of_episodes produces empty items" do
      season = build_season(%{season_number: 1, number_of_episodes: 0, episodes: []})
      tv = build_tv_series(%{seasons: [season]})

      view_model = SeriesDetail.build(%{entity: tv, progress: nil, progress_records: []}, [], nil, nil)

      [%SeasonView{items: []}] = view_model.seasons
    end
  end

  describe "compose/1 — DB-backed assembly" do
    test "returns :not_found when entity_id matches no library record" do
      assert :not_found == SeriesDetail.compose(Ecto.UUID.generate())
    end

    test "returns {:error, :wrong_type} for movie entities" do
      movie = create_standalone_movie()
      record_present(create_linked_file(%{movie_id: movie.id}))

      assert {:error, :wrong_type} = SeriesDetail.compose(movie.id)
    end

    test "tv_series with no Item: seasons mirror library; no future seasons" do
      tv = create_tv_series_with_one_episode("Sample Series")

      assert {:ok, view_model} = SeriesDetail.compose(tv.id)
      assert view_model.tracking_status == nil
      assert [%SeasonView{kind: :library, items: items}] = view_model.seasons
      assert Enum.all?(items, &match?(%EpisodeListItem.Library{}, &1))
    end

    test "tv_series with tracked Item and future-season releases produces a future bucket" do
      tv = create_tv_series_with_one_episode("Tracked Series", tmdb_id: "424242")

      item =
        create_tracking_item(%{
          tmdb_id: 424_242,
          name: "Tracked Series",
          library_container_type: :tv_series,
          library_container_id: tv.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 7),
        season_number: 2,
        episode_number: 1,
        released: false
      })

      assert {:ok, view_model} = SeriesDetail.compose(tv.id)
      assert view_model.tracking_status == :watching

      assert [
               %SeasonView{kind: :library, season_number: 1},
               %SeasonView{kind: :future, season_number: 2, items: [item]}
             ] = view_model.seasons

      assert %EpisodeListItem.Upcoming{episode_number: 1, sub_status: :unaired} = item
    end

    test "ignored Item yields no upcoming rows even when releases exist" do
      tv = create_tv_series_with_one_episode("Ignored Series", tmdb_id: "555555")

      item =
        create_tracking_item(%{
          tmdb_id: 555_555,
          name: "Ignored Series",
          library_container_type: :tv_series,
          library_container_id: tv.id
        })

      {:ok, _} = ReleaseTracking.ignore_item(item)

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 7),
        season_number: 2,
        episode_number: 1
      })

      assert {:ok, view_model} = SeriesDetail.compose(tv.id)
      # Just the library season — no future bucket because the Item is ignored.
      assert [%SeasonView{kind: :library}] = view_model.seasons
      assert view_model.tracking_status == :ignored
    end
  end

  # --- Test helpers ---

  defp season_with_episodes(season_number, number_of_episodes, present_numbers) do
    episodes = build_episodes(present_numbers)

    build_season(%{
      season_number: season_number,
      number_of_episodes: number_of_episodes,
      episodes: episodes
    })
  end

  defp build_episodes(numbers) do
    Enum.map(numbers, fn n -> build_episode(%{episode_number: n, name: "Episode #{n}"}) end)
  end

  defp release_map(overrides) do
    Map.merge(
      %{
        season_number: 1,
        episode_number: 1,
        air_date: Date.add(Date.utc_today(), 7),
        title: "Untitled",
        released: false,
        in_library: false
      },
      overrides
    )
  end

  defp create_tv_series_with_one_episode(name, opts \\ []) do
    tv = create_tv_series(%{name: name})

    if tmdb_id = Keyword.get(opts, :tmdb_id) do
      create_external_id(%{tv_series_id: tv.id, source: "tmdb", external_id: tmdb_id})
    end

    season = create_season(%{tv_series_id: tv.id, season_number: 1, number_of_episodes: 1})

    episode =
      create_episode(%{
        season_id: season.id,
        episode_number: 1,
        name: "Pilot",
        content_url: "/media/test/#{tv.id}-s01e01.mkv"
      })

    # Library Schema v2 Phase 2 Task B: WatchedFile attaches to an
    # Episode-level PlayableItem, not the TVSeries directly.
    playable_item = create_playable_item_for_episode(episode)

    record_present(
      create_linked_file(%{
        playable_item_id: playable_item.id,
        file_path: episode.content_url
      })
    )

    tv
  end
end
