defmodule MediaCentaur.WatchHistory.Views.PlaybackActivity do
  @moduledoc """
  Shapes watch-history reads into the snapshot the Playback status tile renders:
  a short recent-watched feed, the timestamp of the most recent write (the
  honest "recorder is alive" signal — see the status-page persona), and lifetime
  totals. Pure read-shaping; no PubSub, no caching. `StatusLive` calls `snapshot/0`
  on mount and after `watch_history:events` messages, and uses `empty/0` for the
  disconnected mount.

  ## Snapshot shape

      %{recent: [%{title: String.t(), kind: :movie | :episode | :video_object, at: DateTime.t()}],
        last_write_at: DateTime.t() | nil,
        lifetime: %{hours: non_neg_integer(), titles: non_neg_integer(), streak: non_neg_integer()}}
  """
  alias MediaCentaur.WatchHistory

  @recent_limit 5

  @spec empty() :: map()
  def empty, do: %{recent: [], last_write_at: nil, lifetime: %{hours: 0, titles: 0, streak: 0}}

  @spec snapshot() :: map()
  def snapshot do
    recent = Enum.map(WatchHistory.recent_events(@recent_limit), &shape_event/1)
    stats = WatchHistory.stats()

    %{
      recent: recent,
      last_write_at: List.first(recent) && List.first(recent).at,
      lifetime: %{
        hours: round((stats.total_seconds || 0.0) / 3600),
        titles: stats.total_count,
        streak: stats.streak
      }
    }
  end

  defp shape_event(event) do
    %{title: event.title, kind: event.entity_type, at: event.completed_at}
  end
end
