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

  describe "hero flagging (nearest releases are heroes)" do
    test "the nearest two events are flagged hero?, the rest are not" do
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

      assert Enum.map(ordered, & &1.hero?) == [true, true, false, false]
    end

    test "fewer than two events: all present events are heroes" do
      item = tv_item()
      one = release(item, %{title: "only", air_date: days(2), season_number: 1, episode_number: 1})

      feed = UpcomingFeed.build([one], armed_context())

      assert [%{hero?: true}] = all_events(feed)
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
end
