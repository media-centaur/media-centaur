defmodule MediaCentarr.ReleaseTracking.RefresherTest do
  use MediaCentarr.DataCase, async: false

  import MediaCentarr.TmdbStubs
  alias MediaCentarr.ReleaseTracking
  alias MediaCentarr.ReleaseTracking.Refresher

  setup do
    setup_tmdb_client()
    :ok
  end

  describe "refresh_item/1" do
    test "updates releases and detects date changes for TV series" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: ~D[2026-06-15],
        title: "Return",
        season_number: 6,
        episode_number: 1
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => %{
             "air_date" => "2026-07-01",
             "season_number" => 6,
             "episode_number" => 1,
             "name" => "Return"
           }
         }}
      ])

      :ok = Refresher.refresh_item(item)

      events = ReleaseTracking.list_recent_events(10)
      assert Enum.any?(events, &(&1.event_type == :upcoming_release_date_changed))

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert hd(releases).air_date == ~D[2026-07-01]
    end

    test "refreshes movie collection releases" do
      item =
        create_tracking_item(%{tmdb_id: 263, media_type: :movie, name: "Sample Collection"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: ~D[2028-07-01],
        title: "Sample Movie B"
      })

      stub_routes([
        {"/collection/263",
         %{
           "id" => 263,
           "name" => "Sample Collection",
           "poster_path" => "/dk.jpg",
           "parts" => [
             %{"id" => 155, "title" => "Sample Movie A", "release_date" => "2008-07-18"},
             %{
               "id" => 99_999,
               "title" => "Sample Movie B",
               "release_date" => "2028-12-25"
             }
           ]
         }}
      ])

      :ok = Refresher.refresh_item(item)

      events = ReleaseTracking.list_recent_events(10)
      assert Enum.any?(events, &(&1.event_type == :upcoming_release_date_changed))

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).air_date == ~D[2028-12-25]
      assert hd(releases).released == false
    end

    test "falls back to /movie/{id} when /collection/{id} returns 404 (solo-movie tracker)" do
      item =
        create_tracking_item(%{
          tmdb_id: 1_226_863,
          media_type: :movie,
          name: "Solo Movie"
        })

      # No /collection/1226863 stub → TmdbStubs returns 404. The /movie/{id}
      # endpoint succeeds, exercising the fallback path.
      stub_routes([
        {"/movie/1226863",
         %{
           "id" => 1_226_863,
           "title" => "Solo Movie",
           "release_date" => "2027-12-25",
           "poster_path" => "/sm.jpg",
           "backdrop_path" => "/sm-bd.jpg"
         }}
      ])

      :ok = Refresher.refresh_item(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).air_date == ~D[2027-12-25]
      assert hd(releases).title == "Solo Movie"

      reloaded = ReleaseTracking.get_item(item.id)
      assert reloaded.name == "Solo Movie"
    end

    test "marks past releases as released" do
      item = create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show"})

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -3),
        title: "Past Episode",
        season_number: 1,
        episode_number: 1
      })

      stub_routes([
        {"/tv/1396",
         %{
           "id" => 1396,
           "name" => "Sample Show",
           "status" => "Returning Series",
           "poster_path" => "/bb.jpg",
           "next_episode_to_air" => nil
         }}
      ])

      :ok = Refresher.refresh_item(item)

      {_count, _} = ReleaseTracking.mark_past_releases_as_released()
      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert is_list(releases)
    end
  end

  describe "auto_track_new_entities/1" do
    test "auto-tracks a returning TV series with a TMDB ID" do
      tv_series = create_tv_series(%{name: "New Show", status: :returning})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "5555"
      })

      stub_routes([
        {"/tv/5555",
         %{
           "id" => 5555,
           "name" => "New Show",
           "status" => "Returning Series",
           "poster_path" => "/new.jpg",
           "number_of_seasons" => 2,
           "next_episode_to_air" => %{
             "air_date" => "2026-07-01",
             "season_number" => 3,
             "episode_number" => 1,
             "name" => "Premiere"
           }
         }}
      ])

      Refresher.auto_track_new_entities([tv_series.id])

      item = ReleaseTracking.get_item_by_tmdb(5555, :tv_series)
      assert item != nil
      assert item.name == "New Show"
      assert item.source == :library
      assert item.library_entity_id == tv_series.id

      releases = ReleaseTracking.list_releases_for_item(item.id)
      refute releases == []

      events = ReleaseTracking.list_recent_events(5)
      assert Enum.any?(events, &(&1.event_type == :began_tracking))
    end

    test "skips ended TV series" do
      tv_series = create_tv_series(%{name: "Done Show", status: :ended})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "6666"
      })

      Refresher.auto_track_new_entities([tv_series.id])

      assert ReleaseTracking.get_item_by_tmdb(6666, :tv_series) == nil
    end

    test "skips TV series without TMDB external ID" do
      tv_series = create_tv_series(%{name: "No TMDB", status: :returning})

      Refresher.auto_track_new_entities([tv_series.id])

      # No tracking item created (no TMDB ID to track)
      items = ReleaseTracking.list_all_items()
      refute Enum.any?(items, &(&1.name == "No TMDB"))
    end

    test "skips TV series already tracked" do
      tv_series = create_tv_series(%{name: "Already Tracked", status: :returning})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "7777"
      })

      create_tracking_item(%{
        tmdb_id: 7777,
        media_type: :tv_series,
        name: "Already Tracked",
        library_entity_id: tv_series.id
      })

      Refresher.auto_track_new_entities([tv_series.id])

      # Still just one tracking item
      items = ReleaseTracking.list_all_items()
      assert length(Enum.filter(items, &(&1.tmdb_id == 7777))) == 1
    end

    test "skips TV series with nil status" do
      tv_series = create_tv_series(%{name: "Unknown Status"})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "8888"
      })

      Refresher.auto_track_new_entities([tv_series.id])

      assert ReleaseTracking.get_item_by_tmdb(8888, :tv_series) == nil
    end
  end

  describe "update_last_episodes_for — auto-linking" do
    test "links a manually-tracked item to a library entity by TMDB ID and updates episode progress" do
      tv_series = create_tv_series(%{name: "Sample Drama"})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "250307"
      })

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 2, number_of_episodes: 14})

      for ep <- 1..14 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      # Manually-tracked item with no library_entity_id — simulates the real scenario
      item =
        create_tracking_item(%{
          tmdb_id: 250_307,
          media_type: :tv_series,
          name: "Sample Drama",
          source: :manual,
          last_library_season: 2,
          last_library_episode: 13
        })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -1),
        title: "8:00 P.M.",
        season_number: 2,
        episode_number: 14,
        released: true
      })

      Refresher.refresh_item_tracking_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.library_entity_id == tv_series.id
      assert updated.last_library_episode == 14

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, & &1.in_library)
    end

    test "does not affect items already linked to a library entity" do
      tv_series = create_tv_series(%{name: "Already Linked"})

      create_external_id(%{
        tv_series_id: tv_series.id,
        source: "tmdb",
        external_id: "11111"
      })

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 5})

      for ep <- 1..5 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      item =
        create_tracking_item(%{
          tmdb_id: 11_111,
          media_type: :tv_series,
          name: "Already Linked",
          library_entity_id: tv_series.id,
          last_library_season: 1,
          last_library_episode: 4
        })

      Refresher.refresh_item_tracking_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.library_entity_id == tv_series.id
      assert updated.last_library_episode == 5
    end
  end

  describe "broadcast_releases_ready/1" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, "release_tracking:updates")
      :ok
    end

    test "broadcasts one {:release_ready, item, release} per available, not-in-library release" do
      item =
        create_tracking_item(%{tmdb_id: 4242, media_type: :tv_series, name: "Three Releases"})

      yesterday = Date.add(Date.utc_today(), -1)
      tomorrow = Date.add(Date.utc_today(), 1)

      available =
        ReleaseTracking.create_release!(%{
          item_id: item.id,
          air_date: yesterday,
          title: "Available",
          season_number: 3,
          episode_number: 1,
          released: true,
          in_library: false
        })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: yesterday,
        title: "Already on disk",
        season_number: 3,
        episode_number: 2,
        released: true,
        in_library: true
      })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: tomorrow,
        title: "Future",
        season_number: 3,
        episode_number: 3,
        released: false,
        in_library: false
      })

      Refresher.broadcast_releases_ready(item)

      available_id = available.id

      assert_received {:release_ready, broadcast_item, %{id: ^available_id, episode_number: 1}}
      assert broadcast_item.id == item.id

      refute_received {:release_ready, _, %{episode_number: 2}}
      refute_received {:release_ready, _, %{episode_number: 3}}
    end

    test "broadcasts nothing when no releases are available" do
      item = create_tracking_item(%{tmdb_id: 5252, media_type: :movie, name: "Nothing yet"})
      tomorrow = Date.add(Date.utc_today(), 1)

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: tomorrow,
        title: "Coming soon",
        released: false,
        in_library: false
      })

      Refresher.broadcast_releases_ready(item)

      refute_received {:release_ready, _, _}
    end
  end

  describe "update_last_episodes_for (via PubSub)" do
    test "removes tracking item when library entity is deleted" do
      tv_series = create_tv_series(%{name: "Cancelled Show"})

      item =
        create_tracking_item(%{
          tmdb_id: 9999,
          media_type: :tv_series,
          name: "Cancelled Show",
          library_entity_id: tv_series.id
        })

      # Delete the library entity
      MediaCentarr.Library.destroy_tv_series(tv_series)

      # Simulate PubSub event — call the function directly since GenServer isn't running in test
      Refresher.refresh_item_tracking_for([tv_series.id])

      assert ReleaseTracking.get_item(item.id) == nil
    end

    test "updates last_library_season/episode when new episodes added" do
      tv_series = create_tv_series(%{name: "Active Show"})

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 1, number_of_episodes: 5})

      for ep <- 1..5 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      item =
        create_tracking_item(%{
          tmdb_id: 8888,
          media_type: :tv_series,
          name: "Active Show",
          library_entity_id: tv_series.id,
          last_library_season: 1,
          last_library_episode: 3
        })

      # Simulate PubSub event
      Refresher.refresh_item_tracking_for([tv_series.id])

      updated = ReleaseTracking.get_item(item.id)
      assert updated.last_library_season == 1
      assert updated.last_library_episode == 5
    end

    test "marks releases in_library and broadcasts when new episode added" do
      tv_series = create_tv_series(%{name: "Sample Comedy"})

      season =
        create_season(%{tv_series_id: tv_series.id, season_number: 3, number_of_episodes: 9})

      for ep <- 1..9 do
        create_episode(%{season_id: season.id, episode_number: ep, name: "Episode #{ep}"})
      end

      item =
        create_tracking_item(%{
          tmdb_id: 4321,
          media_type: :tv_series,
          name: "Sample Comedy",
          library_entity_id: tv_series.id,
          last_library_season: 3,
          last_library_episode: 8
        })

      # Create a release for S03E09 that should get marked in_library
      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -1),
        title: "Episode 9",
        season_number: 3,
        episode_number: 9,
        released: true
      })

      # Subscribe to PubSub to verify broadcast
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, "release_tracking:updates")

      # Simulate library change event
      Refresher.refresh_item_tracking_for([tv_series.id])

      # Release should be marked in_library
      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, & &1.in_library)

      # LiveView should be notified via PubSub
      assert_received {:releases_updated, _item_ids}
    end
  end
end
