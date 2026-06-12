defmodule MediaCentaur.WatchHistory.Views.PlaybackActivity do
  @moduledoc """
  Shapes watch-history reads into the snapshot the Playback status tile renders:
  a short recent-watched feed, the timestamp of the most recent write (the
  honest "recorder is alive" signal — see the status-page persona), and lifetime
  totals. Pure read-shaping; no PubSub, no caching. `StatusLive` calls `snapshot/0`
  on mount and after `watch_history:events` messages, and uses `empty/0` for the
  disconnected mount.

  Each recent entry carries two-tier display parts derived from the *stored*
  event title (`primary`/`secondary` — see `title_parts/2`) and a `poster_url`
  resolved from the linked entity via `MediaCentaur.Library.Posters`. Both
  degrade gracefully for deleted entities: parts fall back to the recorded
  string, `poster_url` to `nil` — history outlives titles.

  ## Snapshot shape

      %{recent: [%{title: String.t(), kind: :movie | :episode | :video_object,
                   at: DateTime.t(), primary: String.t(), secondary: String.t(),
                   poster_url: String.t() | nil}],
        last_write_at: DateTime.t() | nil,
        lifetime: %{hours: non_neg_integer(), titles: non_neg_integer(), streak: non_neg_integer()}}
  """
  alias MediaCentaur.Library.Posters
  alias MediaCentaur.WatchHistory

  @recent_limit 5

  # The recorder's episode-title format: "Series S01E03 — Episode Name"
  # (the " — Episode Name" tail is absent for nameless episodes). Parsing the
  # stored string — rather than re-reading the live entity — keeps two-tier
  # display working for entities that were deleted after being watched.
  @episode_title ~r/^(.+) (S\d+E\d+(?: — .+)?)$/

  @spec empty() :: map()
  def empty, do: %{recent: [], last_write_at: nil, lifetime: %{hours: 0, titles: 0, streak: 0}}

  @spec snapshot() :: map()
  def snapshot do
    events = WatchHistory.recent_events(@recent_limit)
    posters = events |> Enum.map(&event_ref/1) |> Enum.reject(&is_nil/1) |> Posters.urls_by_refs()
    recent = Enum.map(events, &shape_event(&1, posters))
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

  @doc """
  Two-tier display parts for a recorded title: `{primary, secondary}`.

  Episode titles split into series (primary) and episode line (secondary);
  titles that don't match the recorded format — and all movies/videos — use
  the full title as primary with a type label as secondary.
  """
  @spec title_parts(:movie | :episode | :video_object, String.t()) :: {String.t(), String.t()}
  def title_parts(:episode, title) do
    case Regex.run(@episode_title, title) do
      [_, series, episode_line] -> {series, episode_line}
      nil -> {title, "Episode"}
    end
  end

  def title_parts(:movie, title), do: {title, "Movie"}
  def title_parts(:video_object, title), do: {title, "Video"}

  defp shape_event(event, posters) do
    {primary, secondary} = title_parts(event.entity_type, event.title)

    %{
      title: event.title,
      kind: event.entity_type,
      at: event.completed_at,
      primary: primary,
      secondary: secondary,
      poster_url: Map.get(posters, event_ref(event))
    }
  end

  defp event_ref(%{entity_type: :movie, movie_id: id}) when not is_nil(id), do: {:movie, id}
  defp event_ref(%{entity_type: :episode, episode_id: id}) when not is_nil(id), do: {:episode, id}

  defp event_ref(%{entity_type: :video_object, video_object_id: id}) when not is_nil(id),
    do: {:video_object, id}

  defp event_ref(_event), do: nil
end
