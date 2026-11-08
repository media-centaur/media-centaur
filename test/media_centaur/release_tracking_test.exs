defmodule MediaCentaur.ReleaseTrackingTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Onboarding
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.TMDB.Title

  describe "persist_release!/2" do
    test "keeps release_type and part_tmdb_id so Differ keys stay stable" do
      {:ok, item} =
        ReleaseTracking.track_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show"})

      release =
        ReleaseTracking.persist_release!(item, %{
          air_date: ~D[2026-07-01],
          title: "S01E01",
          season_number: 1,
          episode_number: 1,
          release_type: "premiere",
          part_tmdb_id: 4242,
          released: false
        })

      assert release.release_type == "premiere"
      assert release.part_tmdb_id == 4242
      assert release.season_number == 1
      assert release.episode_number == 1
    end
  end

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

    # Phase 2 follow-up (Task J): validate_container_pair/1 rejects
    # half-set (type without id, id without type) discriminator pairs —
    # those rows had no meaning and produced confusing query behaviour
    # downstream once the polymorphic FK fanout collapsed.

    test "rejects library_container_id without library_container_type" do
      assert {:error, changeset} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 2_000_001,
                 media_type: :tv_series,
                 name: "Half-set id-only",
                 library_container_id: Ecto.UUID.generate()
               })

      assert errors_on(changeset).library_container_type
    end

    test "rejects library_container_type without library_container_id" do
      assert {:error, changeset} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 2_000_002,
                 media_type: :tv_series,
                 name: "Half-set type-only",
                 library_container_type: :tv_series
               })

      assert errors_on(changeset).library_container_id
    end

    test "accepts both halves unset (library-unlinked tracking item)" do
      assert {:ok, item} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 2_000_003,
                 media_type: :tv_series,
                 name: "Unlinked"
               })

      assert item.library_container_type == nil
      assert item.library_container_id == nil
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
      # `released` is derived from `air_date` — 2026-06-15 is past, so aired.
      assert Release.released?(release, ~D[2026-07-19])
    end
  end

  describe "mark_in_library_releases/1" do
    # A series the library holds: the item's pair is its container's last episode.
    defp linked, do: %{library_container_type: :tv_series, library_container_id: Ecto.UUID.generate()}

    test "marks TV episodes at or below the linked container's last episode" do
      item =
        create_tracking_item(Map.merge(linked(), %{last_library_season: 2, last_library_episode: 5}))

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

    test "a series with no library container marks nothing, whatever its columns say" do
      item = create_tracking_item(%{last_library_season: 2, last_library_episode: 5})
      create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)

      assert [%{in_library: false}] = ReleaseTracking.list_releases_for_item(item.id)
    end

    test "marks released movie releases as in_library" do
      item =
        create_tracking_item(%{
          media_type: :movie,
          name: "Test Collection",
          library_container_id: Ecto.UUID.generate(),
          library_container_type: :movie
        })

      create_tracking_release(%{
        item_id: item.id,
        title: "Old Movie",
        air_date: Date.add(Date.utc_today(), -10),
        part_tmdb_id: 101
      })

      create_tracking_release(%{
        item_id: item.id,
        title: "Upcoming Movie",
        air_date: Date.add(Date.utc_today(), 30),
        part_tmdb_id: 102
      })

      ReleaseTracking.mark_in_library_releases(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      in_library = Enum.filter(releases, & &1.in_library)

      assert length(in_library) == 1
      assert hd(in_library).title == "Old Movie"
    end

    test "does nothing for a movie that is not in the library (no container)" do
      # Sample Title By regression: a movie the user is *tracking* but does
      # not own (library_container_id: nil) must never have its releases
      # flagged in_library just because the digital date has passed — that
      # painted "in your library" on the upcoming page for a movie the user
      # didn't have. Mirrors the TV clause, which guards on last_library_*.
      item = create_tracking_item(%{media_type: :movie, name: "Not Owned"})
      assert item.library_container_id == nil

      create_tracking_release(%{
        item_id: item.id,
        title: "Released Digital",
        released: true,
        release_type: "digital"
      })

      ReleaseTracking.mark_in_library_releases(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, &(not &1.in_library))
    end

    test "does nothing for TV with no library episodes" do
      item = create_tracking_item(%{last_library_season: 0, last_library_episode: 0})
      create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.all?(releases, &(not &1.in_library))
    end

    test "stamps in_library_at on first transition (TV)" do
      item =
        create_tracking_item(Map.merge(linked(), %{last_library_season: 1, last_library_episode: 1}))

      release = create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      assert release.in_library == false
      assert release.in_library_at == nil

      ReleaseTracking.mark_in_library_releases(item)

      reloaded = MediaCentaur.Repo.get!(MediaCentaur.ReleaseTracking.Release, release.id)
      assert reloaded.in_library == true
      assert %DateTime{} = reloaded.in_library_at
    end

    test "does not re-bump in_library_at on subsequent calls (TV)" do
      item =
        create_tracking_item(Map.merge(linked(), %{last_library_season: 1, last_library_episode: 1}))

      release = create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)

      # Backdate in_library_at to a sentinel. A (buggy) re-bump on the second
      # call would overwrite it with the current time, so asserting it is
      # unchanged catches the regression deterministically — no clock-advance
      # sleep needed to make the timestamps distinguishable.
      sentinel = ~U[2000-01-01 00:00:00Z]

      1 =
        force_where(
          from(r in MediaCentaur.ReleaseTracking.Release, where: r.id == ^release.id),
          in_library_at: sentinel
        )

      ReleaseTracking.mark_in_library_releases(item)
      second = MediaCentaur.Repo.get!(MediaCentaur.ReleaseTracking.Release, release.id).in_library_at

      assert second == sentinel
    end

    test "stamps in_library_at on first transition (movie)" do
      item =
        create_tracking_item(%{
          media_type: :movie,
          name: "Test Collection",
          library_container_id: Ecto.UUID.generate(),
          library_container_type: :movie
        })

      release =
        create_tracking_release(%{
          item_id: item.id,
          title: "Old Movie",
          air_date: Date.add(Date.utc_today(), -10)
        })

      ReleaseTracking.mark_in_library_releases(item)

      reloaded = MediaCentaur.Repo.get!(MediaCentaur.ReleaseTracking.Release, release.id)
      assert reloaded.in_library == true
      assert %DateTime{} = reloaded.in_library_at
    end

    test "skips theatrical-only release rows (informational, not downloadable)" do
      item =
        create_tracking_item(%{
          media_type: :movie,
          name: "Mixed Release Collection",
          library_container_id: Ecto.UUID.generate(),
          library_container_type: :movie
        })

      aired = Date.add(Date.utc_today(), -10)

      theatrical =
        create_tracking_release(%{
          item_id: item.id,
          title: "Theatrical Premiere",
          air_date: aired,
          release_type: "theatrical"
        })

      digital =
        create_tracking_release(%{
          item_id: item.id,
          title: "Digital Release",
          air_date: aired,
          release_type: "digital"
        })

      physical =
        create_tracking_release(%{
          item_id: item.id,
          title: "Physical Release",
          air_date: aired,
          release_type: "physical"
        })

      untyped =
        create_tracking_release(%{item_id: item.id, title: "Untyped Release", air_date: aired})

      ReleaseTracking.mark_in_library_releases(item)

      reload = fn id -> MediaCentaur.Repo.get!(MediaCentaur.ReleaseTracking.Release, id) end

      refute reload.(theatrical.id).in_library, "theatrical row must not be auto-marked"
      assert reload.(digital.id).in_library, "digital row should be marked"
      assert reload.(physical.id).in_library, "physical row should be marked"
      assert reload.(untyped.id).in_library, "untyped row should be marked (back-compat)"
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

  describe "list_relevant_releases_for_library_container/2" do
    test "returns [] when no Item is linked to the container" do
      tv = create_tv_series(%{name: "Untracked Show"})

      assert ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series) == []
    end

    test "returns unaired (released: false) releases" do
      tv = create_tv_series(%{name: "Future Show"})

      item =
        create_tracking_item(%{
          name: "Future Show",
          library_container_type: :tv_series,
          library_container_id: tv.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), 14),
        season_number: 3,
        episode_number: 1,
        released: false
      })

      [release] = ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series)
      assert release.season_number == 3
      assert release.episode_number == 1
      refute Release.released?(release)
    end

    test "returns aired-but-not-in-library (released: true, in_library: false) releases" do
      tv = create_tv_series(%{name: "Aired Show"})

      item =
        create_tracking_item(%{
          name: "Aired Show",
          library_container_type: :tv_series,
          library_container_id: tv.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -2),
        season_number: 1,
        episode_number: 5,
        released: true,
        in_library: false
      })

      [release] = ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series)
      assert release.episode_number == 5
      assert Release.released?(release)
      assert release.in_library == false
    end

    test "excludes releases already in the library (in_library: true)" do
      tv = create_tv_series(%{name: "Have It Show"})

      item =
        create_tracking_item(%{
          name: "Have It Show",
          library_container_type: :tv_series,
          library_container_id: tv.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: Date.add(Date.utc_today(), -10),
        season_number: 1,
        episode_number: 1,
        released: true,
        in_library: true
      })

      assert ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series) == []
    end

    test "results are ordered by (season_number, episode_number)" do
      tv = create_tv_series(%{name: "Ordered Show"})

      item =
        create_tracking_item(%{
          name: "Ordered Show",
          library_container_type: :tv_series,
          library_container_id: tv.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-08-01],
        season_number: 2,
        episode_number: 1
      })

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-07-01],
        season_number: 1,
        episode_number: 5
      })

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-07-15],
        season_number: 1,
        episode_number: 6
      })

      results = ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series)

      assert Enum.map(results, &{&1.season_number, &1.episode_number}) ==
               [{1, 5}, {1, 6}, {2, 1}]
    end

    test "filters by media_type — a movie Item with same library_container_id is ignored" do
      tv = create_tv_series(%{name: "Type Filter Show"})

      # Two items at the same library_container_id is unusual (a TV series
      # id used as a `:movie_series` container won't actually resolve), but
      # the function must still scope by media_type — query should only
      # surface tv_series releases.
      tv_item =
        create_tracking_item(%{
          name: "Type Filter Show",
          library_container_type: :tv_series,
          library_container_id: tv.id,
          media_type: :tv_series
        })

      movie_item =
        create_tracking_item(%{
          name: "Type Filter Show",
          library_container_type: :movie_series,
          library_container_id: tv.id,
          media_type: :movie,
          tmdb_id: tv_item.tmdb_id + 1
        })

      create_tracking_release(%{
        item_id: tv_item.id,
        air_date: Date.add(Date.utc_today(), 7),
        season_number: 1,
        episode_number: 1
      })

      create_tracking_release(%{
        item_id: movie_item.id,
        air_date: Date.add(Date.utc_today(), 14)
      })

      results = ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series)
      assert length(results) == 1
      assert hd(results).season_number == 1
    end
  end

  describe "catch_up/2 — the verb's one write path" do
    setup context do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      MediaCentaur.TmdbStubs.setup_artwork_cache(context)
    end

    defp iso(days), do: Date.to_iso8601(Date.add(Date.utc_today(), days))

    # A followed show with four episodes: three aired, one ahead; TMDB's
    # latest aired is S01E03.
    defp followed_show(tmdb_id) do
      MediaCentaur.TmdbStubs.stub_routes([
        {"/tv/#{tmdb_id}/season/1",
         %{
           "season_number" => 1,
           "episodes" =>
             for number <- 1..4 do
               %{
                 "episode_number" => number,
                 "name" => "Episode #{number}",
                 "air_date" => iso((number - 4) * 7 + 7)
               }
             end
         }}
      ])

      create_tracking_item(%{
        tmdb_id: tmdb_id,
        media_type: :tv_series,
        name: "Sample Show",
        rung: :grab,
        payload:
          MediaCentaur.TmdbStubs.tv_detail(%{
            "id" => tmdb_id,
            "name" => "Sample Show",
            "number_of_seasons" => 1,
            "seasons" => [%{"season_number" => 1, "episode_count" => 4}],
            "last_episode_to_air" => %{"season_number" => 1, "episode_number" => 3},
            "next_episode_to_air" => %{"season_number" => 1, "episode_number" => 4, "air_date" => iso(7)},
            "poster_path" => nil,
            "backdrop_path" => nil
          })
      })
    end

    test ":latest sets the point to TMDB's latest aired episode, dismisses the wants it covers and rebuilds the calendar from it" do
      item = followed_show(7001)
      :ok = ReleaseTracking.rebuild_calendar(item)
      assert length(ReleaseTracking.open_wants_for_item(item.id)) == 3

      assert :ok = ReleaseTracking.catch_up(item, :latest)

      assert MediaCentaur.Watchlist.caught_up(7001, :tv_series) == {1, 3}
      assert ReleaseTracking.open_wants_for_item(item.id) == []
      assert [%{episode_number: 4}] = ReleaseTracking.list_releases_for_item(item.id)
      MediaCentaur.TaskAwaits.await_supervised_tasks()
    end

    test "a pair moved earlier widens the calendar and reopens the wants it uncovers; the same pair is a no-op" do
      item = followed_show(7002)
      :ok = ReleaseTracking.catch_up(item, {1, 3})
      assert [%{episode_number: 4}] = ReleaseTracking.list_releases_for_item(item.id)

      assert :ok = ReleaseTracking.catch_up(item, {1, 1})

      assert MediaCentaur.Watchlist.caught_up(7002, :tv_series) == {1, 1}
      assert Enum.map(ReleaseTracking.list_releases_for_item(item.id), & &1.episode_number) == [2, 3, 4]
      assert Enum.map(ReleaseTracking.open_wants_for_item(item.id), & &1.episode_number) == [2, 3]

      assert :ok = ReleaseTracking.catch_up(item, {1, 1})
      MediaCentaur.TaskAwaits.await_supervised_tasks()
    end

    test ":none clears the point — nothing seen yet — so every aired episode is out and wanted; a second :none is a no-op" do
      item = followed_show(7003)
      :ok = ReleaseTracking.catch_up(item, {1, 3})
      assert [%{episode_number: 4}] = ReleaseTracking.list_releases_for_item(item.id)

      assert :ok = ReleaseTracking.catch_up(item, :none)

      assert MediaCentaur.Watchlist.caught_up(7003, :tv_series) == nil

      assert Enum.map(ReleaseTracking.list_releases_for_item(item.id), & &1.episode_number) == [
               1,
               2,
               3,
               4
             ]

      assert Enum.map(ReleaseTracking.open_wants_for_item(item.id), & &1.episode_number) == [1, 2, 3]

      assert :ok = ReleaseTracking.catch_up(item, :none)
      MediaCentaur.TaskAwaits.await_supervised_tasks()
    end

    test "a movie has no point to set" do
      item = create_tracking_item(%{media_type: :movie, name: "Movie A", rung: :grab})
      assert {:error, %Ecto.Changeset{}} = ReleaseTracking.catch_up(item, {1, 1})
    end
  end

  describe "Onboarding.onboard/1" do
    # Onboarding warms the poster; the image CDN is stubbed so the
    # download lands under a per-test data dir instead of logging a
    # failure the test never asserts.
    setup context do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      MediaCentaur.TmdbStubs.setup_artwork_cache(context)
    end

    defp past(days), do: Date.to_iso8601(Date.add(Date.utc_today(), -days))
    defp future(days), do: Date.to_iso8601(Date.add(Date.utc_today(), days))

    test "following a series catches the person up to TMDB's latest aired episode: the aired episodes are rows and had, no want opens" do
      MediaCentaur.TmdbStubs.stub_routes([
        {"/tv/5555/season/1",
         %{
           "season_number" => 1,
           "episodes" => [
             %{"episode_number" => 1, "name" => "Pilot", "air_date" => past(20)},
             %{"episode_number" => 2, "name" => "Second", "air_date" => past(10)},
             %{"episode_number" => 3, "name" => "Future Ep", "air_date" => future(30)}
           ]
         }},
        {"/tv/5555",
         %{
           "id" => 5555,
           "name" => "New Show",
           "status" => "Returning Series",
           "poster_path" => "/new.jpg",
           "number_of_seasons" => 1,
           "last_episode_to_air" => %{"season_number" => 1, "episode_number" => 2},
           "next_episode_to_air" => %{
             "air_date" => future(30),
             "season_number" => 1,
             "episode_number" => 3,
             "name" => "Future Ep"
           }
         }}
      ])

      create_title_intent(%{
        tmdb_id: 5555,
        media_type: :tv_series,
        name: "New Show",
        rung: :grab,
        stored: false
      })

      {:ok, item} =
        Onboarding.onboard(
          Title.new!(%{tmdb_id: 5555, media_type: :tv_series, name: "New Show", poster_path: "/new.jpg"})
        )

      assert item.last_library_season == 0
      assert MediaCentaur.Watchlist.caught_up(5555, :tv_series) == {1, 2}

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert Enum.sort(Enum.map(releases, & &1.episode_number)) == [1, 2, 3]
      assert ReleaseTracking.open_wants_for_item(item.id) == []

      item = Map.put(ReleaseTracking.get_item(item.id), :releases, releases)
      assert %{out: [], next: next} = ReleaseTracking.Calendar.read(item, {1, 2}, Date.utc_today())
      assert Date.to_iso8601(next.air_date) == future(30)
      MediaCentaur.TaskAwaits.await_supervised_tasks()
    end

    test "a series TMDB has aired nothing of is followed with no point" do
      MediaCentaur.TmdbStubs.stub_routes([
        {"/tv/6666/season/1",
         %{
           "season_number" => 1,
           "episodes" => [%{"episode_number" => 1, "name" => "Pilot", "air_date" => future(30)}]
         }},
        {"/tv/6666",
         %{
           "id" => 6666,
           "name" => "Coming Show",
           "status" => "In Production",
           "poster_path" => "/mix.jpg",
           "number_of_seasons" => 1,
           "next_episode_to_air" => %{
             "air_date" => future(30),
             "season_number" => 1,
             "episode_number" => 1,
             "name" => "Pilot"
           }
         }}
      ])

      create_title_intent(%{
        tmdb_id: 6666,
        media_type: :tv_series,
        name: "Coming Show",
        rung: :follow,
        stored: false
      })

      {:ok, item} =
        Onboarding.onboard(
          Title.new!(%{
            tmdb_id: 6666,
            media_type: :tv_series,
            name: "Coming Show",
            poster_path: "/mix.jpg"
          })
        )

      assert MediaCentaur.Watchlist.caught_up(6666, :tv_series) == nil
      assert [%{episode_number: 1} = only] = ReleaseTracking.list_releases_for_item(item.id)
      refute Release.released?(only)
      MediaCentaur.TaskAwaits.await_supervised_tasks()
    end

    test "tracks a movie with theatrical and digital releases" do
      MediaCentaur.TmdbStubs.stub_routes([
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
        Onboarding.onboard(
          Title.new!(%{
            tmdb_id: 9999,
            media_type: :movie,
            name: "Upcoming Movie",
            poster_path: "/movie.jpg"
          })
        )

      assert item.tmdb_id == 9999
      assert item.media_type == :movie

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 2

      theatrical = Enum.find(releases, &(&1.release_type == "theatrical"))
      assert theatrical.air_date == ~D[2027-01-01]

      digital = Enum.find(releases, &(&1.release_type == "digital"))
      assert digital.air_date == ~D[2027-03-15]
    end

    test "tracks a movie with no release date" do
      MediaCentaur.TmdbStubs.stub_routes([
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
        Onboarding.onboard(
          Title.new!(%{tmdb_id: 8888, media_type: :movie, name: "Mystery Film", poster_path: nil})
        )

      assert item.tmdb_id == 8888

      releases = ReleaseTracking.list_releases_for_item(item.id)
      assert length(releases) == 1
      assert hd(releases).air_date == nil
    end

    test "tracking an already-tracked TV series returns :already_tracked" do
      MediaCentaur.TmdbStubs.stub_routes([
        {"/tv/7777",
         %{
           "id" => 7777,
           "name" => "Sample Show",
           "status" => "Returning Series",
           "poster_path" => "/sample.jpg",
           "number_of_seasons" => 1,
           "next_episode_to_air" => %{
             "air_date" => "2027-06-01",
             "season_number" => 1,
             "episode_number" => 1,
             "name" => "Premiere"
           }
         }}
      ])

      result =
        Title.new!(%{tmdb_id: 7777, media_type: :tv_series, name: "Sample Show", poster_path: nil})

      {:ok, item} = Onboarding.onboard(result)

      assert {:error, :already_tracked} = Onboarding.onboard(result)

      # The duplicate attempt must not disturb the existing item or its releases.
      assert ReleaseTracking.get_item_by_tmdb(7777, :tv_series).id == item.id
      assert length(ReleaseTracking.list_releases_for_item(item.id)) == 1
    end

    test "tracking an already-tracked movie returns :already_tracked" do
      MediaCentaur.TmdbStubs.stub_routes([
        {"/movie/6060",
         %{
           "id" => 6060,
           "title" => "Sample Movie",
           "status" => "Planned",
           "release_date" => nil,
           "poster_path" => nil
         }}
      ])

      result = Title.new!(%{tmdb_id: 6060, media_type: :movie, name: "Sample Movie", poster_path: nil})

      {:ok, item} = Onboarding.onboard(result)

      assert {:error, :already_tracked} = Onboarding.onboard(result)
      assert ReleaseTracking.get_item_by_tmdb(6060, :movie).id == item.id
    end
  end

  describe "list_releases_between/3" do
    test "returns empty list when no releases exist" do
      monday = ~D[2026-04-27]
      sunday = ~D[2026-05-03]
      assert ReleaseTracking.list_releases_between(monday, sunday) == []
    end

    test "returns releases with air_date within the window" do
      item = create_tracking_item(%{name: "The Show"})

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

    test "carries release_type so callers can label theatrical dates" do
      item = create_tracking_item(%{name: "Sample Movie", media_type: :movie, tmdb_id: 88_001})

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-04-29],
        release_type: "theatrical"
      })

      [row] = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])

      assert row.release_type == "theatrical"
      assert row.item.media_type == :movie
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
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.release_tracking_updates())
      :ok
    end

    test "broadcasts :releases_updated and :item_removed with TMDB key for TV items" do
      item =
        create_tracking_item(%{tmdb_id: 7777, media_type: :tv_series, name: "Going Away"})

      assert {:ok, _} = ReleaseTracking.delete_item(item)

      assert_received {:releases_updated, [_]}
      # `:item_removed` carries the TMDB-standard tmdb_type ("tv"), the same
      # form Acquisition stores in `Grab.tmdb_type` — so the consumer's
      # cancel-by-key lookup matches. See `tmdb_type_for/1`.
      assert_received {:item_removed, "7777", "tv"}
    end

    test "broadcasts :item_removed with movie type for movie items" do
      item = create_tracking_item(%{tmdb_id: 8888, media_type: :movie, name: "Going Away"})

      assert {:ok, _} = ReleaseTracking.delete_item(item)
      assert_received {:item_removed, "8888", "movie"}
    end
  end

  describe "list_releases_between/3 artwork" do
    defp seed_cached(role, media_type, tmdb_id) do
      data_dir = put_tmp_data_dir()
      dir = Path.join([data_dir, "images", "tmdb", "#{media_type}-#{tmdb_id}"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, role), "bytes")
    end

    test "a row dresses from the library entity where it has the image and the referenced cache where not" do
      series = create_tv_series(%{name: "Owned Show"})

      create_image(%{
        owner_type: :tv_series,
        owner_id: series.id,
        role: "logo",
        content_url: "s/logo.png"
      })

      seed_cached("backdrop.jpg", :tv_series, 9101)

      item =
        create_tracking_item(%{
          name: "Owned Show",
          tmdb_id: 9101,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: series.id
        })

      create_tracking_release(%{
        item_id: item.id,
        air_date: ~D[2026-04-28],
        season_number: 1,
        episode_number: 1
      })

      assert [row] = ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])
      assert row.logo_url == "/media-images/s/logo.png"
      assert row.backdrop_url == "/media-images/images/tmdb/tv_series-9101/backdrop.jpg"
    end

    test "a row for a title the library does not own dresses from the referenced cache, nil when it is empty" do
      seed_cached("logo.png", :tv_series, 9102)
      tracked = create_tracking_item(%{name: "Tracked Show", tmdb_id: 9102, media_type: :tv_series})

      create_tracking_release(%{
        item_id: tracked.id,
        air_date: ~D[2026-04-28],
        season_number: 1,
        episode_number: 2
      })

      bare = create_tracking_item(%{name: "Bare Show", tmdb_id: 9103, media_type: :tv_series})

      create_tracking_release(%{
        item_id: bare.id,
        air_date: ~D[2026-04-29],
        season_number: 1,
        episode_number: 1
      })

      assert [tracked_row, bare_row] =
               ReleaseTracking.list_releases_between(~D[2026-04-27], ~D[2026-05-03])

      assert tracked_row.logo_url == "/media-images/images/tmdb/tv_series-9102/logo.png"
      assert tracked_row.backdrop_url == nil
      assert bare_row.logo_url == nil
      assert bare_row.backdrop_url == nil
    end
  end

  describe "tmdb_type_for/1" do
    test ":tv_series translates to TMDB-standard \"tv\"" do
      assert ReleaseTracking.tmdb_type_for(:tv_series) == "tv"
    end

    test ":movie translates to \"movie\"" do
      assert ReleaseTracking.tmdb_type_for(:movie) == "movie"
    end
  end

  describe "detach_dangling_containers/0 — a lost containers_deleted is repaired" do
    # `detach_library_containers/1` runs on a `containers_deleted` PubSub
    # message; a lost one left an item pointing at a deleted container — for
    # a title nobody follows, still tracked and still grabbing. The sweep
    # now finds such items by state (campaign durable-work, F10).
    test "an item pointing at a container that no longer exists is detached and reconciled" do
      item =
        create_tracking_item(%{
          tmdb_id: 6171,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: Ecto.UUID.generate(),
          rung: nil
        })

      assert ReleaseTracking.detach_dangling_containers() == 1
      refute ReleaseTracking.get_item(item.id)
    end

    test "an item pointing at a container that exists is left alone" do
      series = create_entity(%{type: :tv_series, name: "Sample Show"})

      item =
        create_tracking_item(%{
          tmdb_id: 6172,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: series.id,
          rung: nil
        })

      assert ReleaseTracking.detach_dangling_containers() == 0
      assert ReleaseTracking.get_item(item.id).library_container_id == series.id
    end
  end

  describe "detach_library_containers/1" do
    # Deleting a series from the library unlinks it and reconciles. The
    # rung decides what survives: a title nobody follows goes, and a title
    # a person put on the ladder keeps following it (ADR-066: the library is
    # never a reason — only a person starts tracking, so only a person stops it).
    test "a title nobody asked for stops being tracked" do
      container_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          tmdb_id: 6161,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: container_id,
          rung: nil
        })

      assert ReleaseTracking.detach_library_containers([container_id]) == 1
      refute ReleaseTracking.get_item(item.id)
    end

    test "a title a person follows keeps following it after the library drops it" do
      container_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          tmdb_id: 6163,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: container_id,
          rung: :grab
        })

      assert ReleaseTracking.detach_library_containers([container_id]) == 1

      kept = ReleaseTracking.get_item(item.id)
      assert kept, "the rung is the person's; losing the files does not lower it"
      assert kept.library_container_id == nil
    end

    test "leaves items linked to other containers untouched" do
      other_container_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          tmdb_id: 6262,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: other_container_id
        })

      assert ReleaseTracking.detach_library_containers([Ecto.UUID.generate()]) == 0
      assert ReleaseTracking.get_item(item.id).library_container_id == other_container_id
    end
  end

  describe "tracking artwork lifecycle" do
    defp put_tmp_data_dir do
      data_dir =
        Path.join(System.tmp_dir!(), "rt_artwork_#{System.unique_integer([:positive])}")

      File.mkdir_p!(data_dir)
      config = :persistent_term.get({MediaCentaur.Settings.Config, :config})
      :persistent_term.put({MediaCentaur.Settings.Config, :config}, Map.put(config, :data_dir, data_dir))
      on_exit(fn -> File.rm_rf!(data_dir) end)
      data_dir
    end

    defp seed_artwork_dir(data_dir, media_type, tmdb_id) do
      dir = Path.join([data_dir, "images", "tmdb", "#{media_type}-#{tmdb_id}"])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "poster.jpg"), "jpg")
      dir
    end

    test "delete_item/1 leaves artwork in place — the TmdbArtwork sweep owns removal" do
      data_dir = put_tmp_data_dir()
      item = create_tracking_item(%{tmdb_id: 4242, media_type: :tv_series})
      artwork_dir = seed_artwork_dir(data_dir, item.media_type, item.tmdb_id)

      assert {:ok, _} = ReleaseTracking.delete_item(item)
      assert File.dir?(artwork_dir)
    end

    test "untracked artwork ages out through the sweep; tracked artwork is held" do
      data_dir = put_tmp_data_dir()
      item = create_tracking_item(%{tmdb_id: 5151, media_type: :tv_series})
      held_dir = seed_artwork_dir(data_dir, :tv_series, item.tmdb_id)
      released_dir = seed_artwork_dir(data_dir, :tv_series, 999_999)

      aged = System.os_time(:second) - 8 * 86_400
      File.touch!(held_dir, aged)
      File.touch!(released_dir, aged)

      assert MediaCentaur.TmdbArtwork.sweep() == 1
      assert File.dir?(held_dir)
      refute File.dir?(released_dir)
    end
  end

  describe "tracked_refs/0" do
    test "is the {tmdb_id, media_type} set of every tracked item" do
      assert ReleaseTracking.tracked_refs() == MapSet.new()

      create_tracking_item(%{tmdb_id: 200, media_type: :tv_series, name: "Sample Show"})
      create_tracking_item(%{tmdb_id: 777, media_type: :movie, name: "Sample Movie"})

      assert ReleaseTracking.tracked_refs() == MapSet.new([{200, :tv_series}, {777, :movie}])
    end
  end
end
