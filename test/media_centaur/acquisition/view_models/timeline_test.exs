defmodule MediaCentaur.Acquisition.ViewModels.TimelineTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.Event
  alias MediaCentaur.Acquisition.ViewModels.Timeline
  alias MediaCentaur.Acquisition.ViewModels.Timeline.{Resolver, Run}

  @base ~U[2026-11-05 01:00:00Z]

  defp event(kind, seconds_ago, payload \\ %{}) do
    struct(Event, %{
      kind: kind,
      payload: payload,
      occurred_at: DateTime.add(@base, -seconds_ago, :second),
      denormalized_pursuit_title: "Sample Show"
    })
  end

  defp resolver do
    Resolver.new([
      {%{id: "t-1", release_title: "Sample.Show.S04E01", torrent_hash: nil},
       [%{season_number: 4, episode_number: 1}]},
      {%{id: "t-4", release_title: "Sample.Show.S04E04", torrent_hash: nil},
       [%{season_number: 4, episode_number: 4}]},
      {%{id: "t-5", release_title: "Sample.Show.S04E05", torrent_hash: nil},
       [%{season_number: 4, episode_number: 5}]}
    ])
  end

  describe "build/3 — runs" do
    test "consecutive events that read the same fold into one run with a count, a span and their subjects" do
      events = [
        event("auto_cancelled", 0, %{
          "reason" => "download_failed",
          "detail" => "Aborted",
          "target_id" => "t-1"
        }),
        event("auto_cancelled", 1, %{
          "reason" => "download_failed",
          "detail" => "Aborted",
          "target_id" => "t-4"
        }),
        event("auto_cancelled", 2, %{
          "reason" => "download_failed",
          "detail" => "Aborted",
          "target_id" => "t-5"
        }),
        event("pursuit_started", 900, %{"origin" => "auto"})
      ]

      timeline = Timeline.build("p-1", events, resolver())

      assert %Timeline{total_events: 4, total_runs: 2, rest: []} = timeline
      assert [%Run{count: 3} = abandoned, %Run{count: 1}] = timeline.recent
      assert abandoned.entry.summary == "Release abandoned — download failed"
      assert abandoned.subjects == ["S04E01", "S04E04", "S04E05"]
      assert abandoned.last_at == @base
      assert abandoned.first_at == DateTime.add(@base, -2, :second)
    end

    test "events of two kinds written in the same second fold by kind, not by their write order" do
      events = [
        event("target_changed", 0, %{"target_id" => "t-1"}),
        event("auto_cancelled", 0, %{"reason" => "download_failed", "target_id" => "t-1"}),
        event("target_changed", 0, %{"target_id" => "t-4"}),
        event("auto_cancelled", 0, %{"reason" => "download_failed", "target_id" => "t-4"})
      ]

      timeline = Timeline.build("p-1", events, resolver())

      assert timeline.total_runs == 2

      assert Enum.map(timeline.recent, &{&1.entry.kind, &1.count}) == [
               {"auto_cancelled", 2},
               {"target_changed", 2}
             ]
    end

    test "a different detail breaks the run — two client messages are two rows" do
      events = [
        event("auto_cancelled", 0, %{"reason" => "download_failed", "detail" => "Aborted"}),
        event("auto_cancelled", 1, %{"reason" => "download_failed", "detail" => "Repair failed"})
      ]

      assert %Timeline{total_runs: 2} = Timeline.build("p-1", events, Resolver.empty())
    end

    test "runs read newest first whatever order the events arrive in" do
      events = [
        event("pursuit_started", 300),
        event("release_picked", 100),
        event("download_started", 200)
      ]

      kinds = Enum.map(Timeline.build("p-1", events, Resolver.empty()).recent, & &1.entry.kind)
      assert kinds == ["release_picked", "download_started", "pursuit_started"]
    end
  end

  describe "build/3 — recent and the rest" do
    test "the newest six runs are recent; the older ones are the rest, paged by page/0" do
      events =
        for i <- 0..9,
            do: event(if(rem(i, 2) == 0, do: "download_started", else: "health_changed"), i * 60)

      timeline = Timeline.build("p-1", events, Resolver.empty())

      assert timeline.total_runs == 10
      assert length(timeline.recent) == 6
      assert length(timeline.rest) == 4
      assert Timeline.page() == 50
    end

    test "no events is an empty timeline" do
      assert %Timeline{total_events: 0, total_runs: 0, recent: [], rest: []} =
               Timeline.build("p-1", [], Resolver.empty())
    end
  end
end
