defmodule MediaCentaur.ReleaseTrackingTest do
  use MediaCentaur.DataCase, async: false

  import Ecto.Query
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Release
  alias MediaCentaur.ReleaseTracking.TitleResult

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
      # `released` is derived from `air_date` — 2026-06-15 is past, so aired.
      assert Release.released?(release, ~D[2026-07-19])
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

    test "classifies a release aired today as released even with a stale stored flag" do
      # Simulates the across-midnight window: a row that was stamped
      # `released: false` yesterday whose `air_date` is today. The old
      # nightly sweep had to run to flip the flag; deriving `released` from
      # `air_date` on read fixes the stale-across-midnight class of bug.
      item = create_tracking_item()

      ReleaseTracking.create_release!(%{
        item_id: item.id,
        air_date: Date.utc_today(),
        title: "Aired Today",
        season_number: 1,
        episode_number: 1,
        released: false
      })

      %{upcoming: upcoming, released: released} = ReleaseTracking.list_releases()
      assert Enum.map(released, & &1.title) == ["Aired Today"]
      assert upcoming == []
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
      # Carolina Caroline regression: a movie the user is *tracking* but does
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
      item = create_tracking_item(%{last_library_season: 1, last_library_episode: 1})
      release = create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      assert release.in_library == false
      assert release.in_library_at == nil

      ReleaseTracking.mark_in_library_releases(item)

      reloaded = MediaCentaur.Repo.get!(MediaCentaur.ReleaseTracking.Release, release.id)
      assert reloaded.in_library == true
      assert %DateTime{} = reloaded.in_library_at
    end

    test "does not re-bump in_library_at on subsequent calls (TV)" do
      item = create_tracking_item(%{last_library_season: 1, last_library_episode: 1})
      release = create_tracking_release(%{item_id: item.id, season_number: 1, episode_number: 1})

      ReleaseTracking.mark_in_library_releases(item)

      # Backdate in_library_at to a sentinel. A (buggy) re-bump on the second
      # call would overwrite it with the current time, so asserting it is
      # unchanged catches the regression deterministically — no clock-advance
      # sleep needed to make the timestamps distinguishable.
      sentinel = ~U[2000-01-01 00:00:00Z]

      {1, _} =
        MediaCentaur.Repo.update_all(
          from(r in MediaCentaur.ReleaseTracking.Release, where: r.id == ^release.id),
          set: [in_library_at: sentinel]
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
      MediaCentaur.Repo.update_all(
        from(r in MediaCentaur.ReleaseTracking.Release, where: r.id == ^release.id),
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

      MediaCentaur.Repo.update_all(
        from(r in MediaCentaur.ReleaseTracking.Release, where: r.id == ^release.id),
        set: [in_library: true, in_library_at: two_days_ago]
      )

      %{released: released, upcoming: upcoming} = ReleaseTracking.list_releases()
      refute Enum.any?(released, &(&1.id == release.id))
      refute Enum.any?(upcoming, &(&1.id == release.id))
    end
  end

  describe "list_relevant_releases_for_library_container/2" do
    test "returns [] when no Item is linked to the container" do
      tv = create_tv_series(%{name: "Untracked Show"})

      assert ReleaseTracking.list_relevant_releases_for_library_container(tv.id, :tv_series) == []
    end

    test "returns [] when the linked Item has status :ignored" do
      tv = create_tv_series(%{name: "Ignored Show"})

      item =
        create_tracking_item(%{
          name: "Ignored Show",
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
        library_container_type: :tv_series,
        library_container_id: tracked.id
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
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    test "preserves TMDB's relevance order across movie and TV results" do
      # The multi endpoint ranks across types — a TV show may outrank
      # every movie. The merge must not regroup by type (the old
      # movies-then-tv concatenation starved TV out of the capped
      # dropdown entirely).
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 200,
          "media_type" => "tv",
          "name" => "Test Show",
          "first_air_date" => "2025-01-01",
          "poster_path" => "/t.jpg"
        },
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Test Movie",
          "release_date" => "2026-07-01",
          "poster_path" => "/m.jpg",
          "overview" => "A test movie overview."
        },
        %{
          "id" => 201,
          "media_type" => "tv",
          "name" => "Test Show Two",
          "first_air_date" => "2021-01-01",
          "poster_path" => nil
        }
      ])

      results = ReleaseTracking.search_tmdb("test")

      assert [
               %TitleResult{tmdb_id: 200, media_type: :tv_series, name: "Test Show", year: "2025"},
               %TitleResult{tmdb_id: 100, media_type: :movie, name: "Test Movie", year: "2026"},
               %TitleResult{tmdb_id: 201, media_type: :tv_series, name: "Test Show Two", year: "2021"}
             ] = results

      assert hd(results).poster_path == "/t.jpg"
      assert Enum.at(results, 1).overview == "A test movie overview."
    end

    test "carries each result's backdrop path for the plan flow's cinematic shell" do
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Test Movie",
          "release_date" => "2026-07-01",
          "poster_path" => "/m.jpg",
          "backdrop_path" => "/m-backdrop.jpg"
        },
        %{
          "id" => 200,
          "media_type" => "tv",
          "name" => "Test Show",
          "first_air_date" => "2025-01-01",
          "poster_path" => "/t.jpg",
          "backdrop_path" => "/t-backdrop.jpg"
        }
      ])

      assert [movie, show] = ReleaseTracking.search_tmdb("test")
      assert movie.backdrop_path == "/m-backdrop.jpg"
      assert show.backdrop_path == "/t-backdrop.jpg"
    end

    test "drops person results from the multi search" do
      MediaCentaur.TmdbStubs.stub_search_multi([
        %{"id" => 999, "media_type" => "person", "name" => "Test Actor"},
        %{
          "id" => 100,
          "media_type" => "movie",
          "title" => "Test Movie",
          "release_date" => "2026-07-01",
          "poster_path" => "/m.jpg"
        }
      ])

      assert [%TitleResult{tmdb_id: 100, media_type: :movie}] = ReleaseTracking.search_tmdb("test")
    end

    test "marks already tracked results" do
      create_tracking_item(%{tmdb_id: 200, media_type: :tv_series, name: "Test Show"})

      MediaCentaur.TmdbStubs.stub_search_multi([
        %{
          "id" => 200,
          "media_type" => "tv",
          "name" => "Test Show",
          "first_air_date" => "2025-01-01",
          "poster_path" => "/t.jpg"
        }
      ])

      results = ReleaseTracking.search_tmdb("test")
      assert hd(results).tracked? == true
    end

    test "returns empty list for no results" do
      MediaCentaur.TmdbStubs.stub_search_multi([])
      assert ReleaseTracking.search_tmdb("xyznonexistent") == []
    end
  end

  describe "search_tmdb/1 — trailing year in the query" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    # The multi endpoint matches the whole query string against titles —
    # "Test Movie 1999" matches nothing. A trailing year must instead be
    # sent as the year filter of the per-type endpoints.
    defp stub_year_search(movie_results, tv_results, multi_results) do
      Req.Test.stub(:tmdb, fn conn ->
        params = URI.decode_query(conn.query_string)

        cond do
          String.contains?(conn.request_path, "search/movie") ->
            if params["year"],
              do: Req.Test.json(conn, %{"results" => movie_results}),
              else: Req.Test.json(conn, %{"results" => []})

          String.contains?(conn.request_path, "search/tv") ->
            if params["first_air_date_year"],
              do: Req.Test.json(conn, %{"results" => tv_results}),
              else: Req.Test.json(conn, %{"results" => []})

          String.contains?(conn.request_path, "search/multi") ->
            Req.Test.json(conn, %{"results" => multi_results})

          true ->
            Req.Test.json(conn, %{"results" => []})
        end
      end)
    end

    test "a trailing year routes to the year-filtered movie and tv searches" do
      stub_year_search(
        [%{"id" => 100, "title" => "Test Movie", "release_date" => "1999-07-01", "popularity" => 5.0}],
        [],
        []
      )

      assert [%TitleResult{tmdb_id: 100, media_type: :movie, year: "1999"}] =
               ReleaseTracking.search_tmdb("Test Movie 1999")
    end

    test "a parenthesized trailing year is treated the same" do
      stub_year_search(
        [%{"id" => 100, "title" => "Test Movie", "release_date" => "1999-07-01", "popularity" => 5.0}],
        [],
        []
      )

      assert [%TitleResult{tmdb_id: 100, media_type: :movie}] =
               ReleaseTracking.search_tmdb("Test Movie (1999)")
    end

    test "movie and tv year results merge by TMDB popularity" do
      stub_year_search(
        [%{"id" => 100, "title" => "Test Movie", "release_date" => "1999-07-01", "popularity" => 5.0}],
        [%{"id" => 200, "name" => "Test Show", "first_air_date" => "1999-01-01", "popularity" => 10.0}],
        []
      )

      assert [
               %TitleResult{tmdb_id: 200, media_type: :tv_series},
               %TitleResult{tmdb_id: 100, media_type: :movie}
             ] = ReleaseTracking.search_tmdb("Test 1999")
    end

    test "falls back to a year-less multi search of the stripped title when the year filter finds nothing" do
      Req.Test.stub(:tmdb, fn conn ->
        params = URI.decode_query(conn.query_string)

        # Only the stripped title may reach the multi fallback — the
        # full "Test Movie 1997" string would match no TMDB title.
        if String.contains?(conn.request_path, "search/multi") and params["query"] == "Test Movie" do
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 100,
                "media_type" => "movie",
                "title" => "Test Movie",
                "release_date" => "2000-07-01",
                "poster_path" => "/m.jpg"
              }
            ]
          })
        else
          Req.Test.json(conn, %{"results" => []})
        end
      end)

      assert [%TitleResult{tmdb_id: 100, media_type: :movie, year: "2000"}] =
               ReleaseTracking.search_tmdb("Test Movie 1997")
    end

    test "a bare year is a plain query, not a year filter" do
      Req.Test.stub(:tmdb, fn conn ->
        if String.contains?(conn.request_path, "search/multi") do
          Req.Test.json(conn, %{
            "results" => [
              %{
                "id" => 300,
                "media_type" => "movie",
                "title" => "1999",
                "release_date" => "2009-01-01",
                "poster_path" => nil
              }
            ]
          })
        else
          Req.Test.json(conn, %{"results" => []})
        end
      end)

      assert [%TitleResult{tmdb_id: 300, media_type: :movie}] = ReleaseTracking.search_tmdb("1999")
    end
  end

  describe "track_from_search/2" do
    setup do
      MediaCentaur.TmdbStubs.setup_tmdb_client()
      :ok
    end

    test "tracks a TV series with custom scope" do
      MediaCentaur.TmdbStubs.stub_routes([
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

      MediaCentaur.TmdbStubs.stub_routes([
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
      refute Release.released?(hd(releases))
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
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.release_tracking_updates())
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

  describe "logo_url_for_item/2" do
    test "prefers the library container's logo when present" do
      container_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          name: "Has both",
          library_container_type: :tv_series,
          library_container_id: container_id,
          logo_path: "images/tracking/9001/logo.png"
        })

      library_logos = %{container_id => "/media-images/library/some-other-logo.png"}

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

    test "falls back to the tracking item's logo when the library container has no logo" do
      container_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          name: "Imported but no library logo",
          library_container_type: :tv_series,
          library_container_id: container_id,
          logo_path: "images/tracking/9003/logo.png"
        })

      # library_logos has no entry for this container_id
      assert ReleaseTracking.logo_url_for_item(item, %{}) ==
               "/media-images/images/tracking/9003/logo.png"
    end

    test "returns nil when neither library logo nor tracking logo is available" do
      item = create_tracking_item(%{name: "No logos at all"})

      assert ReleaseTracking.logo_url_for_item(item, %{}) == nil
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

  describe "prune_events/1" do
    test "deletes events inserted before the cutoff" do
      item = create_tracking_item()

      ReleaseTracking.create_event!(%{
        item_id: item.id,
        item_name: item.name,
        event_type: :began_tracking,
        description: "Old enough to prune"
      })

      future_cutoff = DateTime.add(DateTime.utc_now(), 60, :second)

      assert ReleaseTracking.prune_events(future_cutoff) == 1
      assert ReleaseTracking.list_recent_events(10) == []
    end

    test "keeps events newer than the cutoff" do
      item = create_tracking_item()

      ReleaseTracking.create_event!(%{
        item_id: item.id,
        item_name: item.name,
        event_type: :began_tracking,
        description: "Fresh"
      })

      past_cutoff = DateTime.add(DateTime.utc_now(), -90 * 24 * 3600, :second)

      assert ReleaseTracking.prune_events(past_cutoff) == 0
      assert [_event] = ReleaseTracking.list_recent_events(10)
    end
  end

  describe "detach_library_containers/1" do
    test "nils the container link on matching items and keeps tracking alive" do
      container_id = Ecto.UUID.generate()

      item =
        create_tracking_item(%{
          tmdb_id: 6161,
          media_type: :tv_series,
          library_container_type: :tv_series,
          library_container_id: container_id
        })

      assert ReleaseTracking.detach_library_containers([container_id]) == 1

      detached = ReleaseTracking.get_item(item.id)
      assert detached.library_container_id == nil
      assert detached.library_container_type == nil
      assert detached.status == item.status
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

  describe "tracking artwork cleanup" do
    defp put_tmp_data_dir do
      data_dir =
        Path.join(System.tmp_dir!(), "rt_artwork_#{System.unique_integer([:positive])}")

      File.mkdir_p!(data_dir)
      config = :persistent_term.get({MediaCentaur.Config, :config})
      :persistent_term.put({MediaCentaur.Config, :config}, Map.put(config, :data_dir, data_dir))
      on_exit(fn -> File.rm_rf!(data_dir) end)
      data_dir
    end

    defp seed_artwork_dir(data_dir, tmdb_id) do
      dir = Path.join([data_dir, "images", "tracking", to_string(tmdb_id)])
      File.mkdir_p!(dir)
      File.write!(Path.join(dir, "poster.jpg"), "jpg")
      dir
    end

    test "delete_item/1 removes the item's artwork directory from disk" do
      data_dir = put_tmp_data_dir()
      item = create_tracking_item(%{tmdb_id: 4242})
      artwork_dir = seed_artwork_dir(data_dir, item.tmdb_id)

      assert {:ok, _} = ReleaseTracking.delete_item(item)
      refute File.dir?(artwork_dir)
    end

    test "sweep_orphaned_artwork/0 removes directories with no tracking item and keeps the rest" do
      data_dir = put_tmp_data_dir()
      item = create_tracking_item(%{tmdb_id: 5151})
      kept_dir = seed_artwork_dir(data_dir, item.tmdb_id)
      orphan_dir = seed_artwork_dir(data_dir, 999_999)

      assert ReleaseTracking.sweep_orphaned_artwork() == 1
      assert File.dir?(kept_dir)
      refute File.dir?(orphan_dir)
    end

    test "sweep_orphaned_artwork/0 returns 0 when no data_dir is configured" do
      config = :persistent_term.get({MediaCentaur.Config, :config})
      :persistent_term.put({MediaCentaur.Config, :config}, Map.put(config, :data_dir, nil))

      assert ReleaseTracking.sweep_orphaned_artwork() == 0
    end
  end
end
