defmodule MediaCentaurWeb.Storybook.Acquisition.PursuitTimeline do
  @moduledoc """
  History for a pursuit: the recent runs, the full log behind its
  disclosure, and Show more — including a Sample Title Eo-sized fixture
  (30 episodes, a thousand events) to prove the DOM stays bounded.
  """

  use PhoenixStorybook.Story, :component

  alias MediaCentaur.Acquisition.Pursuits.Event
  alias MediaCentaur.Acquisition.ViewModels.Timeline
  alias MediaCentaur.Acquisition.ViewModels.Timeline.Resolver

  def function, do: &MediaCentaurWeb.Components.Acquisition.PursuitTimeline.timeline/1
  def render_source, do: :function

  def template do
    """
    <div class="max-w-2xl">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :runs_and_log,
        description:
          "A short history whose repeated events fold into counted rows; the older rows wait behind the log's disclosure.",
        attributes: %{vm: Timeline.build("story-runs", runs_events(), small_resolver())}
      },
      %Variation{
        id: :log_open,
        description:
          "The same history with the full log open: the first page of older rows and no Show more.",
        attributes: %{
          vm: Timeline.build("story-runs", runs_events(), small_resolver()),
          disclosures: MapSet.new(["history-log-story-runs"])
        }
      },
      %Variation{
        id: :large_log,
        description:
          "The worst case: 30 episodes, about a thousand events. Six recent rows, then the log's first fifty and Show more.",
        attributes: %{
          vm: Timeline.build("story-large", large_events(), large_resolver()),
          disclosures: MapSet.new(["history-log-story-large"])
        }
      },
      %Variation{
        id: :empty,
        description: "No events yet (just created).",
        attributes: %{vm: Timeline.build("story-empty", [], Resolver.empty())}
      }
    ]
  end

  @base ~U[2026-11-05 01:27:00Z]

  defp event(kind, seconds_ago, payload) do
    struct(Event, %{
      pursuit_id: "story",
      kind: kind,
      payload: payload,
      occurred_at: DateTime.add(@base, -seconds_ago, :second),
      denormalized_pursuit_title: "Sample Show"
    })
  end

  defp target(id, season, episode) do
    {%{
       id: id,
       release_title: "Sample.Show.S#{pad(season)}E#{pad(episode)}.1080p.WEB-DL",
       torrent_hash: "hash-#{id}"
     }, [%{season_number: season, episode_number: episode}]}
  end

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp small_resolver, do: Resolver.new([target("t1", 4, 1), target("t4", 4, 4), target("t5", 4, 5)])

  # Three releases abandoned in one sweep, their replacements grabbed, the
  # goal cancelled — plus enough older rows to need the log.
  defp runs_events do
    failed = %{"reason" => "download_failed", "detail" => "Aborted, cannot be completed"}

    [
      event("pursuit_cancelled", 0, %{"cancelled_by" => "user", "reason" => "user_request"}),
      event("download_started", 700, %{"client" => "sabnzbd", "infohash" => "hash-t1"}),
      event("download_started", 700, %{"client" => "sabnzbd", "infohash" => "hash-t4"}),
      event("download_started", 700, %{"client" => "sabnzbd", "infohash" => "hash-t5"}),
      event("target_changed", 720, %{"target_id" => "t1"}),
      event("target_changed", 720, %{"target_id" => "t4"}),
      event("target_changed", 720, %{"target_id" => "t5"}),
      event("auto_cancelled", 720, Map.put(failed, "target_id", "t1")),
      event("auto_cancelled", 720, Map.put(failed, "target_id", "t4")),
      event("auto_cancelled", 720, Map.put(failed, "target_id", "t5")),
      event("health_changed", 1500, %{"from_state" => "downloading", "to_state" => "error"}),
      event("health_changed", 1500, %{"from_state" => "downloading", "to_state" => "error"}),
      event("health_changed", 1500, %{"from_state" => "downloading", "to_state" => "error"}),
      event("identity_verified", 3600, %{"file_path" => "/library/Sample Show/S04E06.mkv"}),
      event("release_picked", 7200, %{
        "release_title" => "Sample.Show.S04.1080p.WEB-DL",
        "indexer" => "ExampleIndexer",
        "quality" => "1080p"
      }),
      event("pursuit_started", 7300, %{"origin" => "auto"})
    ]
  end

  # Thirty episodes; three of them fail every fifteen minutes for twelve
  # hours (48 releases each), the rest land on the first or second try.
  defp large_resolver do
    Resolver.new(
      for season <- 1..5, episode <- 1..6, do: target("t#{season}#{episode}", season, episode)
    )
  end

  defp large_events do
    failed = %{"reason" => "download_failed", "detail" => "Aborted, cannot be completed"}
    failing = ["t41", "t44", "t45"]

    loop =
      for round <- 0..47, id <- failing do
        at = round * 900 + 60

        [
          event("download_started", at, %{"client" => "sabnzbd", "infohash" => "hash-#{id}"}),
          event("target_changed", at + 10, %{"target_id" => id}),
          event("auto_cancelled", at + 10, Map.put(failed, "target_id", id)),
          event("health_changed", at + 600, %{"from_state" => "downloading", "to_state" => "error"})
        ]
      end

    landed =
      for season <- 1..5, episode <- 1..6, "t#{season}#{episode}" not in failing do
        at = 46_000 + season * 600 + episode * 30

        [
          event("identity_verified", at, %{
            "file_path" => "/library/Sample Show/S#{pad(season)}E#{pad(episode)}.mkv"
          }),
          event("download_started", at + 900, %{
            "client" => "sabnzbd",
            "infohash" => "hash-t#{season}#{episode}"
          })
        ]
      end

    [event("pursuit_cancelled", 0, %{"cancelled_by" => "user", "reason" => "user_request"})] ++
      List.flatten(loop) ++
      List.flatten(landed) ++
      [
        event("release_picked", 49_400, %{
          "release_title" => "Sample.Show.S01-S05.1080p",
          "indexer" => "ExampleIndexer",
          "quality" => "1080p"
        }),
        event("pursuit_started", 49_500, %{"origin" => "auto"})
      ]
  end
end
