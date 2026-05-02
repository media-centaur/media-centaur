defmodule MediaCentarr.ReleaseTrackingTest do
  use MediaCentarr.DataCase, async: false

  import Ecto.Query
  alias MediaCentarr.ReleaseTracking

  describe "track_item/1" do
    test "creates a tracking item" do
      assert {:ok, item} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 1396,
                 media_type: :tv_series,
                 name: "Sample Show"
               })

      assert item.tmdb_id == 1396
      assert item.media_type == :tv_series
      assert item.status == :watching
      assert item.source == :library
    end

    test "enforces unique tmdb_id + media_type" do
      {:ok, _} =
        ReleaseTracking.track_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show"})

      assert {:error, changeset} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 1396,
                 media_type: :tv_series,
                 name: "Sample Show"
               })

      assert errors_on(changeset).tmdb_id
    end
  end

  describe "ignore_item/1 and watch_item/1" do
    test "toggles item status" do
      item = create_tracking_item(%{name: "Test Show"})
      assert item.status == :watching

      {:ok, ignored} = ReleaseTracking.ignore_item(item)
      assert ignored.status == :ignored

      {:ok, watching} = ReleaseTracking.watch_item(ignored)
      assert watching.status == :watching
    end
  end

  describe "list_watching_items/0" do
    test "returns only items with status :watching" do
      create_tracking_item(%{name: "Watching Show", tmdb_id: 100})
      ignored = create_tracking_item(%{name: "Ignored Show", tmdb_id: 200})
      ReleaseTracking.ignore_item(ignored)

      items = ReleaseTracking.list_watching_items()
      assert length(items) == 1
      assert hd(items).name == "Watching Show"
    end
  end

  describe "tracking_status/1" do
    test "returns status for tracked item" do
      create_tracking_item(%{tmdb_id: 1396, media_type: :tv_series})
      assert ReleaseTracking.tracking_status({1396, :tv_series}) == :watching
    end

    test "returns nil for untracked item" do
      assert ReleaseTracking.tracking_status({9999, :movie}) == nil
    end
  end

  describe "create_release/1" do
    test "creates a release for an item" do
      item = create_tracking_item()

      assert {:ok, release} =
               ReleaseTracking.create_release(%{
                 item_id: item.id,
                 air_date: ~D[2026-06-15],
                 title: "Pilot",
                 season_number: 1,
                 episode_number: 1
               })

      assert release.air_date == ~D[2026-06-15]
      assert release.released == false
    end
  end

  describe "list_releases/0" do
    test "returns releases grouped as upcoming and released" do
      item = create_tracking_item()

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 30),
        title: "Future Episode",
        season_number: 1,
        episode_number: 1
      })

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -5),
        title: "Past Episode",
        season_number: 1,
        episode_number: 0,
        released: true
      })

      %{upcoming: upcoming, released: released} = ReleaseTracking.list_releases()
      assert length(upcoming) == 1
      assert hd(upcoming).title == "Future Episode"
      assert length(released) == 1
      assert hd(released).title == "Past Episode"
    end
  end

  describe "mark_in_library_releases/1" do
    test "marks TV episodes at or below last library episode" do
      item =
        create_tracking_item(%{
          last_library_season: 2,
          last_library_episode: 5
        })

      # In library: S01E01, S02E03, S02E05
      create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})
      create_tracking_release(%{item_id: item.id, season_number: 2, episode_number: 3})
      create_tracking_release(%{item_id: item.id, season_number: 2, episode_number: 5})
      # Not in library: S02E06, S03E01
      create_tracking_release(%{item_id: item.id, season_number: 2, episode_number: 6})
      create_tracking_release(%{item_id: item.id, season_number: 3, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      in_library = Enum.filter(releases, & &1.in_library)
      not_in_library = Enum.reject(releases, & &1.in_library)

      assert length(in_library) == 3
      assert length(not_in_library) == 2
      episode_keys = Enum.map(not_in_library, &{&1.season_number, &1.episode_number})
      assert {2, 6} in episode_keys
      assert {3, 1} in episode_keys
    end

    test "marks released movie releases as in_library" do
      item = create_tracking_item(%{media_type: :movie, name: "Test Collection"})

      create_tracking_release(%{item_id: item.id, title: "Old Movie", released: true})
      create_tracking_release(%{item_id: item.id, title: "Upcoming Movie", released: false})

      ReleaseTracking.mark_in_library_releases(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      in_library = Enum.filter(releases, & &1.in_library)

      assert length(in_library) == 1
      assert hd(in_library).title == "Old Movie"
    end

    test "does nothing for TV with no library episodes" do
      item = create_tracking_item(%{last_library_season: 0, last_library_episode: 0})
      create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, &(not &1.in_library))
    end

    test "stamps in_library_at on first transition (TV)" do
      item = create_tracking_item(%{last_library_season: 1, last_library_episode: 1})
      release = create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      assert release.in_library == false
      assert release.in_library_at == nil

      ReleaseTracking.mark_in_library_releases(item)

      reloaded = MediaCentarr.Repo.get!(MediaCentarr.ReleaseTracking.Release, release.id)
      assert reloaded.in_library == true
      assert %DateTime{} = reloaded.in_library_at
    end

    test "does not re-bump in_library_at on subsequent calls (TV)" do
      item = create_tracking_item(%{last_library_season: 1, last_library_episode: 1})
      release = create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)
      first = MediaCentarr.Repo.get!(MediaCentarr.ReleaseTracking.Release, release.id).in_library_at

      # Sleep briefly to ensure any re-bump would have a different timestamp.
      Process.sleep(1100)
      ReleaseTracking.mark_in_library_releases(item)
      second = MediaCentarr.Repo.get!(MediaCentarr.ReleaseTracking.Release, release.id).in_library_at

      assert first == second
    end

    test "stamps in_library_at on first transition (movie)" do
      item = create_tracking_item(%{media_type: :movie, name: "Test Collection"})
      release = create_tracking_release(%{item_id: item.id, title: "Old Movie", released: true})

      ReleaseTracking.mark_in_library_releases(item)

      reloaded = MediaCentarr.Repo.get!(MediaCentarr.ReleaseTracking.Release, release.id)
      assert reloaded.in_library == true
      assert %DateTime{} = reloaded.in_library_at
    end

    test "skips theatrical-only release rows (informational, not downloadable)" do
      item = create_tracking_item(%{media_type: :movie, name: "Mixed Release Collection"})

      theatrical =
        create_tracking_release(%{
          item_id: item.id,
          title: "Theatrical Premiere",
          released: true,
          release_type: "theatrical"
        })

      digital =
        create_tracking_release(%{
          item_id: item.id,
          title: "Digital Release",
          released: true,
          release_type: "digital"
        })

      physical =
        create_tracking_release(%{
          item_id: item.id,
          title: "Physical Release",
          released: true,
          release_type: "physical"
        })

      untyped =
        create_tracking_release(%{item_id: item.id, title: "Untyped Release", released: true})

      ReleaseTracking.mark_in_library_releases(item)

      reload = fn id -> MediaCentarr.Repo.get!(MediaCentarr.ReleaseTracking.Release, id) end

      refute reload.(theatrical.id).in_library, "theatrical row must not be auto-marked"
      assert reload.(digital.id).in_library, "digital row should be marked"
      assert reload.(physical.id).in_library, "physical row should be marked"
      assert reload.(untyped.id).in_library, "untyped row should be marked (back-compat)"
    end
  end

  describe "list_pending_acquirable_releases_for_item/1" do
    test "returns {:error, :not_found} for a missing item" do
      assert {:error, :not_found} =
               ReleaseTracking.list_pending_acquirable_releases_for_item(Ecto.UUID.generate())
    end

    test "returns released, not-in-library, acquirable releases for a TV item, ordered" do
      item = create_tracking_item(%{tmdb_id: 4242, media_type: :tv_series, name: "Other Show"})

      # Out of order on purpose — verify the returned list is sorted (season, episode)
      create_tracking_release(%{
        item_id: item.id,
        season_number: 5,
        episode_number: 2,
        released: true
      })

      create_tracking_release(%{
        item_id: item.id,
        season_number: 5,
        episode_number: 1,
        released: true
      })

      # Not released — must be excluded
      create_tracking_release(%{
        item_id: item.id,
        season_number: 5,
        episode_number: 3,
        released: false
      })

      # Already in library — must be excluded
      create_tracking_release(%{
        item_id: item.id,
        season_number: 4,
        episode_number: 8,
        released: true,
        in_library: true
      })

      assert {:ok, info} = ReleaseTracking.list_pending_acquirable_releases_for_item(item.id)
      assert info.tmdb_id == "4242"
      assert info.tmdb_type == "tv"
      assert info.name == "Other Show"

      assert Enum.map(info.pending_releases, &{&1.season_number, &1.episode_number}) ==
               [{5, 1}, {5, 2}]
    end

    test "excludes theatrical releases (informational only)" do
      item = create_tracking_item(%{media_type: :movie, name: "Sample Movie"})

      create_tracking_release(%{
        item_id: item.id,
        title: "Theatrical",
        released: true,
        release_type: "theatrical"
      })

      create_tracking_release(%{
        item_id: item.id,
        title: "Digital",
        released: true,
        release_type: "digital"
      })

      assert {:ok, %{pending_releases: [_only_one]}} =
               ReleaseTracking.list_pending_acquirable_releases_for_item(item.id)
    end

    test "dedupes movie's digital + physical releases into a single grab key" do
      item = create_tracking_item(%{media_type: :movie, name: "Both Formats"})

      create_tracking_release(%{
        item_id: item.id,
        title: "Digital",
        released: true,
        release_type: "digital"
      })

      create_tracking_release(%{
        item_id: item.id,
        title: "Physical",
        released: true,
        release_type: "physical"
      })

      # Movies have nil season/episode for both rows, so both share the same
      # enqueue key — the orchestrator should only enqueue once.
      assert {:ok, %{pending_releases: pending}} =
               ReleaseTracking.list_pending_acquirable_releases_for_item(item.id)

      assert length(pending) == 1
      assert hd(pending) == %{season_number: nil, episode_number: nil}
    end
  end

  describe "acquirable_release_type?/1" do
    test "true for digital, physical, and nil (back-compat)" do
      assert ReleaseTracking.acquirable_release_type?("digital")
      assert ReleaseTracking.acquirable_release_type?("physical")
      assert ReleaseTracking.acquirable_release_type?(nil)
    end

    test "false for theatrical (informational only)" do
      refute ReleaseTracking.acquirable_release_type?("theatrical")
    end

    test "false for unknown types" do
      refute ReleaseTracking.acquirable_release_type?("streaming")
      refute ReleaseTracking.acquirable_release_type?("tv")
    end
  end

  describe "list_releases/0 — recent-completed linger" do
    test "includes a recently-completed release (within 24h) in the released bucket" do
      item = create_tracking_item()
      yesterday = Date.add(Date.utc_today(), -1)
      twelve_hours_ago = DateTime.add(DateTime.utc_now(:second), -12 * 3600, :second)

      release =
        create_tracking_release(%{
          item_id: item.id,
          air_date: yesterday,
          title: "Just Done",
          season_number: 1,
          episode_number: 1,
          released: true
        })

      # Mark it in_library directly with a recent timestamp.
      MediaCentarr.Repo.update_all(
        from(r in MediaCentarr.ReleaseTracking.Release, where: r.id == ^release.id),
        set: [in_library: true, in_library_at: twelve_hours_ago]
      )

      %{released: released} = ReleaseTracking.list_releases()
      assert Enum.any?(released, &(&1.id == release.id))
    end

    test "excludes a long-completed release (older than 24h)" do
      item = create_tracking_item()
      yesterday = Date.add(Date.utc_today(), -2)
      two_days_ago = DateTime.add(DateTime.utc_now(:second), -48 * 3600, :second)

      release =
        create_tracking_release(%{
          item_id: item.id,
          air_date: yesterday,
          title: "Long Done",
          season_number: 1,
          episode_number: 1,
          released: true
        })

      MediaCentarr.Repo.update_all(
        from(r in MediaCentarr.ReleaseTracking.Release, where: r.id == ^release.id),
        set: [in_library: true, in_library_at: two_days_ago]
      )

      %{released: released, upcoming: upcoming} = ReleaseTracking.list_releases()
      refute Enum.any?(released, &(&1.id == release.id))
      refute Enum.any?(upcoming, &(&1.id == release.id))
    end
  end

  describe "list_releases/0 filtering" do
    test "excludes in_library releases" do
      item = create_tracking_item()

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -5),
        season_number: 1,
        episode_number: 1,
        released: true,
        in_library: true
      })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -3),
        season_number: 1,
        episode_number: 2,
        released: true,
        in_library: false
      })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 10),
        season_number: 1,
        episode_number: 3,
        in_library: false
      })

      %{upcoming: upcoming, released: released} = ReleaseTracking.list_releases()

      assert length(released) == 1
      assert hd(released).episode_number == 2
      assert length(upcoming) == 1
      assert hd(upcoming).episode_number == 3
    end
  end

  describe "suggest_trackable_items/0" do
    test "returns untracked library TV series with active status and TMDB IDs" do
      active = create_tv_series(%{name: "Active Show", status: :returning})

      create_external_id(%{
        tv_series_id: active.id,
        source: "tmdb",
        external_id: "1111"
      })

      suggestions = ReleaseTracking.suggest_trackable_items()
      assert length(suggestions) == 1
      assert hd(suggestions).name == "Active Show"
      assert hd(suggestions).tmdb_id == "1111"
      assert hd(suggestions).tv_series_id == active.id
    end

    test "excludes ended TV series" do
      ended = create_tv_series(%{name: "Done Show", status: :ended})

      create_external_id(%{
        tv_series_id: ended.id,
        source: "tmdb",
        external_id: "2222"
      })

      assert ReleaseTracking.suggest_trackable_items() == []
    end

    test "excludes already tracked TV series" do
      tracked = create_tv_series(%{name: "Already Tracked", status: :returning})

      create_external_id(%{
        tv_series_id: tracked.id,
        source: "tmdb",
        external_id: "3333"
      })

      create_tracking_item(%{
        tmdb_id: 3333,
        media_type: :tv_series,
        name: "Already Tracked",
        library_entity_id: tracked.id
      })

      assert ReleaseTracking.suggest_trackable_items() == []
    end

    test "excludes TV series without TMDB external ID" do
      _no_tmdb = create_tv_series(%{name: "No TMDB", status: :returning})
      assert ReleaseTracking.suggest_trackable_items() == []
    end

    test "includes TV series with nil status (pre-existing library items)" do
      unknown = create_tv_series(%{name: "Unknown"})

      create_external_id(%{
        tv_series_id: unknown.id,
        source: "tmdb",
        external_id: "4444"
      })

      suggestions = ReleaseTracking.suggest_trackable_items()
      assert length(suggestions) == 1
      assert hd(suggestions).name == "Unknown"
    end
  end

  describe "search_tmdb/1" do
    setup do
      MediaCentarr.TmdbStubs.setup_tmdb_client()
      :ok
    end

    test "searches both movie and TV endpoints and merges results" do
      MediaCentarr.TmdbStubs.stub_search_both(
        [
          %{
            "id" => 100,
            "title" => "Test Movie",
            "release_date" => "2026-07-01",
            "poster_path" => "/m.jpg"
          }
        ],
        [
          %{
            "id" => 200,
            "name" => "Test Show",
            "first_air_date" => "2025-01-01",
            "poster_path" => "/t.jpg"
          }
        ]
      )

      results = ReleaseTracking.search_tmdb("test")
      assert length(results) == 2

      movie = Enum.find(results, &(&1.media_type == :movie))
      assert movie.tmdb_id == 100
      assert movie.name == "Test Movie"
      assert movie.year == "2026"

      show = Enum.find(results, &(&1.media_type == :tv_series))
      assert show.tmdb_id == 200
      assert show.name == "Test Show"
      assert show.year == "2025"
    end

    test "marks already tracked results" do
      create_tracking_item(%{tmdb_id: 200, media_type: :tv_series, name: "Test Show"})

      MediaCentarr.TmdbStubs.stub_search_both(
        [],
        [
          %{
            "id" => 200,
            "name" => "Test Show",
            "first_air_date" => "2025-01-01",
            "poster_path" => "/t.jpg"
          }
        ]
      )

      results = ReleaseTracking.search_tmdb("test")
      assert hd(results).already_tracked == true
    end

    test "returns empty list for no results" do
      MediaCentarr.TmdbStubs.stub_search_both([], [])
      assert ReleaseTracking.search_tmdb("xyznonexistent") == []
    end
  end

  describe "track_from_search/2" do
    setup do
      MediaCentarr.TmdbStubs.setup_tmdb_client()
      :ok
    end

    test "tracks a TV series with custom scope" do
      MediaCentarr.TmdbStubs.stub_routes([
        {"/tv/5555",
         %{
           "id" => 5555,
           "name" => "New Show",
           "status" => "Returning Series",
           "poster_path" => "/new.jpg",
           "number_of_seasons" => 3,
           "next_episode_to_air" => %{
             "air_date" => "2026-08-01",
             "season_number" => 3,
             "episode_number" => 1,
             "name" => "S3 Premiere"
           }
         }}
      ])

      {:ok, item} =
        ReleaseTracking.track_from_search(
          %{tmdb_id: 5555, media_type: :tv_series, name: "New Show", poster_path: "/new.jpg"},
          %{start_season: 2, start_episode: 5}
        )

      assert item.tmdb_id == 5555
      assert item.source == :manual
      assert item.last_library_season == 2
      assert item.last_library_episode == 5

      events = ReleaseTracking.list_recent_events(5)
      assert Enum.any?(events, &(&1.event_type == :began_tracking))
    end

    test "all upcoming excludes already-released episodes" do
      past_date = Date.to_iso8601(Date.add(Date.utc_today(), -10))
      future_date = Date.to_iso8601(Date.add(Date.utc_today(), 30))

      MediaCentarr.TmdbStubs.stub_routes([
        {"/tv/6666/season/1",
         %{
           "season_number" => 1,
           "episodes" => [
             %{"episode_number" => 1, "name" => "Pilot", "air_date" => past_date},
             %{"episode_number" => 2, "name" => "Second", "air_date" => past_date},
             %{"episode_number" => 3, "name" => "Future Ep", "air_date" => future_date}
           ]
         }},
        {"/tv/6666",
         %{
           "id" => 6666,
           "name" => "Mixed Show",
           "status" => "Returning Series",
           "poster_path" => "/mix.jpg",
           "number_of_seasons" => 1,
           "next_episode_to_air" => %{
             "air_date" => future_date,
             "season_number" => 1,
             "episode_number" => 3,
             "name" => "Future Ep"
           }
         }}
      ])

      {:ok, item} =
        ReleaseTracking.track_from_search(
          %{tmdb_id: 6666, media_type: :tv_series, name: "Mixed Show", poster_path: "/mix.jpg"},
          %{start_season: 0, start_episode: 0}
        )

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).title == "Future Ep"
      assert hd(releases).released == false
    end

    test "tracks a movie with theatrical and digital releases" do
      MediaCentarr.TmdbStubs.stub_routes([
        {"/movie/9999",
         %{
           "id" => 9999,
           "title" => "Upcoming Movie",
           "status" => "In Production",
           "release_date" => "2027-01-01",
           "poster_path" => "/movie.jpg",
           "release_dates" => %{
             "results" => [
               %{
                 "iso_3166_1" => "US",
                 "release_dates" => [
                   %{"release_date" => "2027-01-01T00:00:00.000Z", "type" => 3},
                   %{"release_date" => "2027-03-15T00:00:00.000Z", "type" => 4}
                 ]
               }
             ]
           }
         }}
      ])

      {:ok, item} =
        ReleaseTracking.track_from_search(
          %{tmdb_id: 9999, media_type: :movie, name: "Upcoming Movie", poster_path: "/movie.jpg"},
          %{}
        )

      assert item.tmdb_id == 9999
      assert item.media_type == :movie
      assert item.source == :manual

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 2

      theatrical = Enum.find(releases, &(&1.release_type == "theatrical"))
      assert theatrical.air_date == ~D[2027-01-01]

      digital = Enum.find(releases, &(&1.release_type == "digital"))
      assert digital.air_date == ~D[2027-03-15]

      events = ReleaseTracking.list_recent_events(5)
      assert Enum.any?(events, &(&1.event_type == :began_tracking))
    end

    test "tracks a movie with no release date" do
      MediaCentarr.TmdbStubs.stub_routes([
        {"/movie/8888",
         %{
           "id" => 8888,
           "title" => "Mystery Film",
           "status" => "Planned",
           "release_date" => nil,
           "poster_path" => nil
         }}
      ])

      {:ok, item} =
        ReleaseTracking.track_from_search(
          %{tmdb_id: 8888, media_type: :movie, name: "Mystery Film", poster_path: nil},
          %{}
        )

      assert item.tmdb_id == 8888

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).air_date == nil
    end
  end

  describe "create_event/1" do
    test "creates a change event" do
      item = create_tracking_item()

      assert {:ok, event} =
               ReleaseTracking.create_event(%{
                 item_id: item.id,
                 item_name: item.name,
                 event_type: :began_tracking,
                 description: "Now tracking #{item.name}"
               })

      assert event.event_type == :began_tracking
    end
  end

  describe "list_recent_events/1" do
    test "returns events in reverse chronological order" do
      item = create_tracking_item()

      ReleaseTracking.create_event!(%{
        item_id: item.id,
        item_name: item.name,
        event_type: :began_tracking,
        description: "First"
      })

      ReleaseTracking.create_event!(%{
        item_id: item.id,
        item_name: item.name,
        event_type: :new_season_announced,
        description: "Second"
      })

      events = ReleaseTracking.list_recent_events(10)
      assert length(events) == 2
      assert hd(events).description == "Second"
    end
  end

  describe "update_auto_grab/2" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.release_tracking_updates())
      :ok
    end

    test "persists per-item preferences and broadcasts :releases_updated" do
      item = create_tracking_item(%{tmdb_id: 1111, media_type: :tv_series, name: "Pref"})

      assert {:ok, updated} =
               ReleaseTracking.update_auto_grab(item, %{
                 auto_grab_mode: "off",
                 min_quality: "uhd_4k",
                 max_quality: "uhd_4k",
                 quality_4k_patience_hours: 0,
                 prefer_season_packs: true
               })

      assert updated.auto_grab_mode == "off"
      assert updated.min_quality == "uhd_4k"
      assert updated.max_quality == "uhd_4k"
      assert updated.quality_4k_patience_hours == 0
      assert updated.prefer_season_packs == true

      assert_received {:releases_updated, [_]}
    end

    test "rejects invalid mode" do
      item = create_tracking_item(%{tmdb_id: 2222, media_type: :movie, name: "Bad mode"})

      assert {:error, changeset} =
               ReleaseTracking.update_auto_grab(item, %{auto_grab_mode: "bogus"})

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:auto_grab_mode]
    end

    test "rejects invalid quality value" do
      item = create_tracking_item(%{tmdb_id: 3333, media_type: :movie, name: "Bad quality"})

      assert {:error, changeset} =
               ReleaseTracking.update_auto_grab(item, %{min_quality: "8k_super"})

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:min_quality]
    end

    test "rejects negative patience hours" do
      item = create_tracking_item(%{tmdb_id: 4444, media_type: :movie, name: "Neg"})

      assert {:error, changeset} =
               ReleaseTracking.update_auto_grab(item, %{quality_4k_patience_hours: -1})

      refute changeset.valid?
    end
  end

  describe "list_releases_between/3" do
    test "returns empty list when no releases exist" do
      monday = ~D[2026-04-27]
      sunday = ~D[2026-05-03]
      assert ReleaseTracking.list_releases_between(monday, sunday) == []
    end

    test "returns releases with air_date within the window" do
      item = create_tracking_item(%{name: "The Show", status: :watching})

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-04-28],
        season_number: 2,
        episode_number: 3,
        released: false
      })

      results = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])

      assert length(results) == 1
      row = hd(results)
      assert row.item.id == item.id
      assert row.item.name == "The Show"
      assert row.air_date == ~D[2026-04-28]
      assert row.season_number == 2
      assert row.episode_number == 3
      assert Map.has_key?(row, :status)
      assert Map.has_key?(row, :backdrop_url)
    end

    test "excludes releases outside the date window" do
      item = create_tracking_item(%{name: "Filtered Show"})

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-05-10],
        season_number: 1,
        episode_number: 1
      })

      results = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])
      assert results == []
    end

    test "includes releases on the boundary dates" do
      item = create_tracking_item(%{name: "Boundary Show"})

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-04-27],
        season_number: 1,
        episode_number: 1
      })

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-05-03],
        season_number: 1,
        episode_number: 7
      })

      results = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])
      assert length(results) == 2
    end

    test "excludes ignored items" do
      item = create_tracking_item(%{name: "Ignored Show", tmdb_id: 77_700})
      ReleaseTracking.ignore_item(item)

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-04-28],
        season_number: 1,
        episode_number: 1
      })

      results = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])
      assert results == []
    end

    test "respects the limit option" do
      item = create_tracking_item(%{name: "Prolific Show"})

      Enum.each(1..5, fn number ->
        create_tracking_release(%{
          item_id: item.id,
          air_date: ~D[2026-04-28],
          season_number: 1,
          episode_number: number
        })
      end)

      results = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03], limit: 3)
      assert length(results) == 3
    end
  end

  describe "delete_item/1 — broadcasts" do
    setup do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.release_tracking_updates())
      :ok
    end

    test "broadcasts :releases_updated and :item_removed with TMDB key for TV items" do
      item =
        create_tracking_item(%{tmdb_id: 7777, media_type: :tv_series, name: "Going Away"})

      assert {:ok, _} = ReleaseTracking.delete_item(item)

      assert_received {:releases_updated, [_]}
      assert_received {:item_removed, "7777", "tv_series"}
    end

    test "broadcasts :item_removed with movie type for movie items" do
      item = create_tracking_item(%{tmdb_id: 8888, media_type: :movie, name: "Going Away"})

      assert {:ok, _} = ReleaseTracking.delete_item(item)
      assert_received {:item_removed, "8888", "movie"}
    end
  end

  describe "logo_url_for_item/2" do
    test "prefers the library entity's logo when present" do
      entity_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          name: "Has both",
          library_entity_id: entity_id,
          logo_path: "images/tracking/9001/logo.png"
        })

      library_logos = %{entity_id => "/media-images/library/some-other-logo.png"}

      assert ReleaseTracking.logo_url_for_item(item, library_logos) ==
               "/media-images/library/some-other-logo.png"
    end

    test "falls back to the tracking item's logo_path when no library logo is available" do
      item =
        create_tracking_item(%{
          name: "Tracked but not imported",
          logo_path: "images/tracking/9002/logo.png"
        })

      assert ReleaseTracking.logo_url_for_item(item, %{}) ==
               "/media-images/images/tracking/9002/logo.png"
    end

    test "falls back to the tracking item's logo when the library entity has no logo" do
      entity_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          name: "Imported but no library logo",
          library_entity_id: entity_id,
          logo_path: "images/tracking/9003/logo.png"
        })

      # library_logos has no entry for this entity_id
      assert ReleaseTracking.logo_url_for_item(item, %{}) ==
               "/media-images/images/tracking/9003/logo.png"
    end

    test "returns nil when neither library logo nor tracking logo is available" do
      item = create_tracking_item(%{name: "No logos at all"})

      assert ReleaseTracking.logo_url_for_item(item, %{}) == nil
    end
  end
end
