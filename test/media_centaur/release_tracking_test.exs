defmodule MediaCentaur.ReleaseTrackingTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.ReleaseTracking

  describe "track_item/1" do
    test "creates a tracking item" do
      assert {:ok, item} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 1396,
                 media_type: :tv_series,
                 name: "Sample Show Eight"
               })

      assert item.tmdb_id == 1396
      assert item.media_type == :tv_series
      assert item.status == :watching
      assert item.source == :library
    end

    test "enforces unique tmdb_id + media_type" do
      {:ok, _} =
        ReleaseTracking.track_item(%{tmdb_id: 1396, media_type: :tv_series, name: "Sample Show Eight"})

      assert {:error, changeset} =
               ReleaseTracking.track_item(%{
                 tmdb_id: 1396,
                 media_type: :tv_series,
                 name: "Sample Show Eight"
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
end
