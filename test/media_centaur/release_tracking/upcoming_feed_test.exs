defmodule MediaCentaur.ReleaseTracking.UpcomingFeedTest do
  @moduledoc """
  Pure unit tests for the Upcoming page view-model. No DB, no network — the
  builder takes already-read facts (today, capability flags, the global
  auto-grab default, and the per-release pursuit linkage) as injected data and
  is a pure function over `Release` structs (with `:item` preloaded).
  """
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.UpcomingFeed
  alias MediaCentaur.TestFactory

  @today ~D[2026-06-14]

  # A context where acquisition is live and the global default auto-grabs
  # everything — the common "trusting automation" posture.
  defp armed_context(overrides \\ %{}) do
    Map.merge(
      %{
        today: @today,
        acquisition_ready?: true,
        auto_grab_default_mode: "all_releases",
        grab_status_by_key: %{}
      },
      overrides
    )
  end

  defp tv_item(overrides \\ %{}) do
    TestFactory.build_tracking_item(
      Map.merge(%{media_type: :tv_series, name: "Sample Show", tmdb_id: 1001}, overrides)
    )
  end

  defp movie_item(overrides \\ %{}) do
    TestFactory.build_tracking_item(
      Map.merge(%{media_type: :movie, name: "Movie A", tmdb_id: 2002}, overrides)
    )
  end

  # A release with its `:item` preloaded (mirrors list_releases/0 output).
  defp release(item, overrides) do
    TestFactory.build_tracking_release(Map.merge(%{item_id: item.id, item: item}, overrides))
  end

  defp days(n), do: Date.add(@today, n)

  # Flatten all bucketed events back into one date-ordered list.
  defp all_events(%UpcomingFeed{buckets: buckets}) do
    Enum.flat_map(UpcomingFeed.bucket_order(), &Map.get(buckets, &1, []))
  end

  defp find_event(feed, title) do
    feed |> all_events() |> Enum.find(&(&1.title == title))
  end

  describe "bucketing by relative time" do
    test "places each release in the right relative-time bucket" do
      item = tv_item()

      releases = [
        release(item, %{title: "today-ep", air_date: days(0), season_number: 1, episode_number: 1}),
        release(item, %{title: "this-week-ep", air_date: days(5), season_number: 1, episode_number: 2}),
        release(item, %{title: "next-week-ep", air_date: days(10), season_number: 1, episode_number: 3}),
        release(item, %{title: "later-ep", air_date: days(20), season_number: 1, episode_number: 4}),
        release(item, %{title: "beyond-ep", air_date: days(90), season_number: 1, episode_number: 5})
      ]

      feed = UpcomingFeed.build(releases, armed_context())

      assert [%{title: "today-ep"}] = feed.buckets.today
      assert [%{title: "this-week-ep"}] = feed.buckets.this_week
      assert [%{title: "next-week-ep"}] = feed.buckets.next_week
      assert [%{title: "later-ep"}] = feed.buckets.later
      assert [%{title: "beyond-ep"}] = feed.buckets.beyond
    end

    test "a release whose air date already passed (within the linger window) buckets into today" do
      item = tv_item()

      yesterday =
        release(item, %{
          title: "just-aired",
          air_date: days(-1),
          released: true,
          season_number: 2,
          episode_number: 1
        })

      feed = UpcomingFeed.build([yesterday], armed_context())

      assert [%{title: "just-aired"}] = feed.buckets.today
    end

    test "events within a bucket are ordered by air date ascending" do
      item = tv_item()

      releases = [
        release(item, %{title: "later", air_date: days(7), season_number: 1, episode_number: 2}),
        release(item, %{title: "sooner", air_date: days(3), season_number: 1, episode_number: 1})
      ]

      feed = UpcomingFeed.build(releases, armed_context())

      assert [%{title: "sooner"}, %{title: "later"}] = feed.buckets.this_week
    end
  end

  describe "status derivation" do
    test "in_library wins regardless of dates — :in_library" do
      item = tv_item()

      release =
        release(item, %{
          title: "landed",
          air_date: days(0),
          in_library: true,
          released: true,
          season_number: 1,
          episode_number: 1
        })

      feed = UpcomingFeed.build([release], armed_context())

      assert find_event(feed, "landed").status == :in_library
    end

    test "theatrical release is informational only — :theatrical_info, never auto-grab" do
      item = movie_item()
      theatrical = release(item, %{title: "in-theaters", air_date: days(20), release_type: "theatrical"})

      feed = UpcomingFeed.build([theatrical], armed_context())

      event = find_event(feed, "in-theaters")
      assert event.status == :theatrical_info
    end

    test "a digital movie release in an armed context is :armed" do
      item = movie_item()
      digital = release(item, %{title: "digital-drop", air_date: days(3), release_type: "digital"})

      feed = UpcomingFeed.build([digital], armed_context())

      assert find_event(feed, "digital-drop").status == :armed
    end

    test "a future episode in an armed context is :armed" do
      item = tv_item()
      ep = release(item, %{title: "armed-ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([ep], armed_context())

      assert find_event(feed, "armed-ep").status == :armed
    end

    test "an active pursuit links the event — :under_pursuit carrying the pursuit id" do
      item = tv_item()

      ep =
        release(item, %{
          title: "grabbing",
          air_date: days(0),
          released: true,
          season_number: 1,
          episode_number: 1
        })

      pursuit_id = Ecto.UUID.generate()

      context =
        armed_context(%{
          grab_status_by_key: %{UpcomingFeed.release_key(ep) => %{pursuit_id: pursuit_id}}
        })

      feed = UpcomingFeed.build([ep], context)

      event = find_event(feed, "grabbing")
      assert event.status == :under_pursuit
      assert event.pursuit_id == pursuit_id
    end

    test "release with no air date is :unscheduled" do
      item = tv_item()

      undated =
        release(item, %{title: "no-date", air_date: nil, season_number: nil, episode_number: nil})

      feed = UpcomingFeed.build([undated], armed_context())

      assert [event] = feed.unscheduled
      assert event.title == "no-date"
      assert event.status == :unscheduled
    end
  end

  describe "armed honesty (only show auto-grabbing when it will actually fire)" do
    test "acquisition not ready → neutral :upcoming, never :armed" do
      item = tv_item()
      ep = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([ep], armed_context(%{acquisition_ready?: false}))

      assert find_event(feed, "ep").status == :upcoming
    end

    test "item opted out of auto-grab (mode \"off\") → neutral :upcoming" do
      item = tv_item(%{auto_grab_mode: "off"})
      ep = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([ep], armed_context())

      assert find_event(feed, "ep").status == :upcoming
    end

    test ~s(global default "off" + item "global" → neutral :upcoming) do
      item = tv_item(%{auto_grab_mode: "global"})
      ep = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([ep], armed_context(%{auto_grab_default_mode: "off"}))

      assert find_event(feed, "ep").status == :upcoming
    end

    test ~s(item "global" inherits an "all_releases" default → :armed) do
      item = tv_item(%{auto_grab_mode: "global"})
      ep = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([ep], armed_context(%{auto_grab_default_mode: "all_releases"}))

      assert find_event(feed, "ep").status == :armed
    end

    test "\"ask\" mode is not full-auto → neutral :upcoming" do
      item = tv_item(%{auto_grab_mode: "ask"})
      ep = release(item, %{title: "ep", air_date: days(3), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([ep], armed_context())

      assert find_event(feed, "ep").status == :upcoming
    end
  end

  describe "prominence (proximity = prominence)" do
    test "nearest is the hero, second-nearest a feature, the rest compact" do
      item = tv_item()

      releases =
        for n <- [0, 3, 10, 20],
            do:
              release(item, %{
                title: "ep#{n}",
                air_date: days(n),
                season_number: 1,
                episode_number: n + 1
              })

      feed = UpcomingFeed.build(releases, armed_context())
      ordered = all_events(feed)

      assert Enum.map(ordered, & &1.prominence) == [:hero, :feature, :compact, :compact]
    end

    test "a lone event is the hero" do
      item = tv_item()
      one = release(item, %{title: "only", air_date: days(2), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([one], armed_context())

      assert [%{prominence: :hero}] = all_events(feed)
    end
  end

  describe "season-drop collapse" do
    test "multiple episodes of one season on the same date collapse to a single :season_drop event" do
      item = tv_item()
      drop = days(8)

      releases =
        for ep <- 1..8 do
          release(item, %{title: "S2E#{ep}", air_date: drop, season_number: 2, episode_number: ep})
        end

      feed = UpcomingFeed.build(releases, armed_context())

      assert [event] = feed.buckets.next_week
      assert event.kind == :season_drop
      assert event.season_number == 2
      assert event.episode_count == 8
    end

    test "episodes of one season on different dates stay as separate episode events" do
      item = tv_item()

      releases = [
        release(item, %{title: "S1E1", air_date: days(3), season_number: 1, episode_number: 1}),
        release(item, %{title: "S1E2", air_date: days(10), season_number: 1, episode_number: 2})
      ]

      feed = UpcomingFeed.build(releases, armed_context())

      assert [%{kind: :episode}] = feed.buckets.this_week
      assert [%{kind: :episode}] = feed.buckets.next_week
    end
  end

  describe "stragglers (tracked, nothing scheduled yet)" do
    test "returns watching items that have no dated release" do
      scheduled = tv_item(%{tmdb_id: 1, name: "Scheduled"})

      scheduled = %{
        scheduled
        | releases: [
            TestFactory.build_tracking_release(%{air_date: ~D[2026-06-20], item_id: scheduled.id})
          ]
      }

      hiatus = tv_item(%{tmdb_id: 2, name: "Hiatus"})

      undated = movie_item(%{tmdb_id: 3, name: "Undated"})

      undated = %{
        undated
        | releases: [TestFactory.build_tracking_release(%{air_date: nil, item_id: undated.id})]
      }

      stragglers = UpcomingFeed.stragglers([scheduled, hiatus, undated])
      names = Enum.map(stragglers, & &1.name)

      assert "Hiatus" in names
      assert "Undated" in names
      refute "Scheduled" in names
    end

    test "carries item id, name, and media type" do
      item = movie_item(%{tmdb_id: 9, name: "Awaiting"})

      assert [straggler] = UpcomingFeed.stragglers([item])
      assert straggler.item_id == item.id
      assert straggler.name == "Awaiting"
      assert straggler.media_type == :movie
    end
  end

  describe "stale past releases (the forecast is about the future)" do
    test "a past theatrical release is dropped from the forecast" do
      item = movie_item()

      past =
        release(item, %{
          title: "old-theatrical",
          air_date: days(-20),
          release_type: "theatrical",
          released: true
        })

      feed = UpcomingFeed.build([past], armed_context())

      refute Enum.any?(all_events(feed), &(&1.title == "old-theatrical"))
    end

    test "a future theatrical release is kept (anticipation)" do
      item = movie_item()

      future =
        release(item, %{title: "future-theatrical", air_date: days(10), release_type: "theatrical"})

      feed = UpcomingFeed.build([future], armed_context())

      assert find_event(feed, "future-theatrical").status == :theatrical_info
    end

    test "a past release that just landed in the library is kept (closure beat)" do
      item = tv_item()

      landed =
        release(item, %{
          title: "landed",
          air_date: days(-1),
          released: true,
          in_library: true,
          season_number: 1,
          episode_number: 1
        })

      feed = UpcomingFeed.build([landed], armed_context())

      assert find_event(feed, "landed").status == :in_library
    end

    test "a past release under an active pursuit is kept" do
      item = tv_item()

      ep =
        release(item, %{
          title: "grabbing",
          air_date: days(-2),
          released: true,
          season_number: 1,
          episode_number: 1
        })

      context =
        armed_context(%{
          grab_status_by_key: %{UpcomingFeed.release_key(ep) => %{pursuit_id: Ecto.UUID.generate()}}
        })

      feed = UpcomingFeed.build([ep], context)

      assert find_event(feed, "grabbing").status == :under_pursuit
    end
  end

  describe "shelf_items/2 — the Incoming shelf presentation" do
    test "flattens buckets nearness-first into one date-ordered list" do
      releases = [
        release(tv_item(%{tmdb_id: 1}), %{
          title: "later-ep",
          air_date: days(20),
          season_number: 1,
          episode_number: 3
        }),
        release(tv_item(%{tmdb_id: 2}), %{
          title: "today-ep",
          air_date: days(0),
          season_number: 1,
          episode_number: 1
        }),
        release(tv_item(%{tmdb_id: 3}), %{
          title: "week-ep",
          air_date: days(5),
          season_number: 1,
          episode_number: 2
        })
      ]

      feed = UpcomingFeed.build(releases, armed_context())
      {items, overflow} = UpcomingFeed.shelf_items(feed, 6)

      assert Enum.map(items, & &1.title) == ["today-ep", "week-ep", "later-ep"]
      assert overflow == 0
    end

    test "caps at the requested size and reports the overflow count" do
      releases =
        for n <- 1..9 do
          release(tv_item(%{tmdb_id: n, name: "Show #{n}"}), %{
            title: "ep-#{n}",
            air_date: days(n),
            season_number: 1,
            episode_number: 1
          })
        end

      feed = UpcomingFeed.build(releases, armed_context())
      {items, overflow} = UpcomingFeed.shelf_items(feed, 6)

      assert length(items) == 6
      assert Enum.map(items, & &1.title) == for(n <- 1..6, do: "ep-#{n}")
      assert overflow == 3
    end

    test "one card per title: same-item releases collapse into the soonest event" do
      movie = movie_item()
      show = tv_item()

      releases = [
        release(movie, %{title: "digital", air_date: days(10), release_type: "digital"}),
        release(movie, %{title: "physical", air_date: days(70), release_type: "physical"}),
        release(show, %{title: "ep-1", air_date: days(1), season_number: 1, episode_number: 1}),
        release(show, %{title: "ep-2", air_date: days(8), season_number: 1, episode_number: 2})
      ]

      feed = UpcomingFeed.build(releases, armed_context())
      {items, overflow} = UpcomingFeed.shelf_items(feed, 6)

      assert Enum.map(items, & &1.title) == ["ep-1", "digital"]
      assert overflow == 0
    end

    test "overflow counts hidden TITLES, not the collapsed later events" do
      releases =
        for n <- 1..8 do
          item = movie_item(%{name: "Movie #{n}", tmdb_id: 3000 + n})

          [
            release(item, %{title: "m#{n}-soon", air_date: days(n), release_type: "digital"}),
            release(item, %{title: "m#{n}-later", air_date: days(n + 40), release_type: "physical"})
          ]
        end

      feed = UpcomingFeed.build(List.flatten(releases), armed_context())
      {items, overflow} = UpcomingFeed.shelf_items(feed, 6)

      assert length(items) == 6
      assert overflow == 2
    end

    test ":all lifts the cap — every title, nothing hidden" do
      releases =
        for n <- 1..9 do
          release(tv_item(%{tmdb_id: n, name: "Show #{n}"}), %{
            title: "ep-#{n}",
            air_date: days(n),
            season_number: 1,
            episode_number: 1
          })
        end

      feed = UpcomingFeed.build(releases, armed_context())
      {items, overflow} = UpcomingFeed.shelf_items(feed, :all)

      assert length(items) == 9
      assert overflow == 0
    end

    test "excludes unscheduled events (they are stragglers, not shelf cards)" do
      item = tv_item()

      releases = [
        release(item, %{title: "dated", air_date: days(1), season_number: 1, episode_number: 1}),
        release(item, %{title: "undated", air_date: nil, season_number: 1, episode_number: 2})
      ]

      feed = UpcomingFeed.build(releases, armed_context())
      {items, overflow} = UpcomingFeed.shelf_items(feed, 6)

      assert Enum.map(items, & &1.title) == ["dated"]
      assert overflow == 0
    end
  end

  describe "shelf_date_label/2 — graduated explicitness" do
    # 2026-06-14 is a Sunday; days(2) = Tue Jun 16, days(10) = Wed Jun 24,
    # days(40) = Fri Jul 24.
    defp shelf_event(feed), do: feed |> UpcomingFeed.shelf_items(6) |> elem(0) |> hd()

    test "an episode airing today reads Tonight" do
      item = tv_item()
      ep = release(item, %{title: "t", air_date: days(0), season_number: 1, episode_number: 1})
      event = shelf_event(UpcomingFeed.build([ep], armed_context()))

      assert UpcomingFeed.shelf_date_label(event, @today) == "Tonight"
    end

    test "a movie landing today reads Today" do
      movie = release(movie_item(), %{title: "m", air_date: days(0), release_type: "digital"})
      event = shelf_event(UpcomingFeed.build([movie], armed_context()))

      assert UpcomingFeed.shelf_date_label(event, @today) == "Today"
    end

    test "a theatrical date that has arrived reads Now" do
      movie = release(movie_item(), %{title: "m", air_date: days(0), release_type: "theatrical"})
      event = shelf_event(UpcomingFeed.build([movie], armed_context()))

      assert UpcomingFeed.shelf_date_label(event, @today) == "Now"
    end

    test "within a week reads as a bare weekday" do
      item = tv_item()
      ep = release(item, %{title: "t", air_date: days(2), season_number: 1, episode_number: 1})
      event = shelf_event(UpcomingFeed.build([ep], armed_context()))

      assert UpcomingFeed.shelf_date_label(event, @today) == "Tue"
    end

    test "within a month reads as weekday plus date" do
      item = tv_item()
      ep = release(item, %{title: "t", air_date: days(10), season_number: 1, episode_number: 1})
      event = shelf_event(UpcomingFeed.build([ep], armed_context()))

      assert UpcomingFeed.shelf_date_label(event, @today) == "Wed Jun 24"
    end

    test "beyond a month drops the weekday" do
      item = tv_item()
      ep = release(item, %{title: "t", air_date: days(40), season_number: 1, episode_number: 1})
      event = shelf_event(UpcomingFeed.build([ep], armed_context()))

      assert UpcomingFeed.shelf_date_label(event, @today) == "Jul 24"
    end
  end
end
