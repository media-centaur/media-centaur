defmodule MediaCentarrWeb.StatusHelpers do
  @moduledoc """
  Pure helper functions for `StatusLive` — formatting, stage classification,
  and display mapping for the operational status page.
  """

  # --- Playback ---

  def derive_playback(sessions) when sessions == %{} do
    %{state: :idle, now_playing: nil, sessions: sessions}
  end

  def derive_playback(sessions) do
    {_entity_id, primary} =
      sessions
      |> Enum.sort_by(fn {_id, session} -> if session.state == :playing, do: 0, else: 1 end)
      |> hd()

    %{state: primary.state, now_playing: primary.now_playing, sessions: sessions}
  end

  @doc """
  Returns true if the WatchProgress record corresponds to the item currently
  playing in the session's `now_playing` map.

  Matches by direct FK ID (`episode_id`, `movie_id`, or `video_object_id`) —
  never by season/episode numbers, which are display metadata only.
  """
  def progress_matches_session?(record, now_playing) do
    (record.episode_id != nil && record.episode_id == now_playing[:episode_id]) ||
      (record.movie_id != nil && record.movie_id == now_playing[:movie_id]) ||
      (record.video_object_id != nil && record.video_object_id == now_playing[:video_object_id])
  end

  # --- Formatting ---

  @doc """
  Formats remaining playback time for the Status playback card.

  Sub-minute durations round up to `"< 1m remaining"` (UIDR-004 forbids
  seconds in user-facing durations). Otherwise delegates to
  `LibraryFormatters.format_human_duration/1` for the canonical `"Xh Ym"` shape.
  """
  def format_remaining(seconds) when seconds <= 0, do: "finished"

  def format_remaining(seconds) when seconds < 60, do: "< 1m remaining"

  def format_remaining(seconds) do
    "#{MediaCentarrWeb.LibraryFormatters.format_human_duration(trunc(seconds))} remaining"
  end

  def format_throughput(rate) when rate == 0.0, do: "—"
  def format_throughput(rate), do: "#{rate}/s"

  def format_duration(nil), do: "—"
  def format_duration(ms) when ms < 1_000, do: "#{round(ms)}ms"
  def format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"
  def format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  def format_datetime(nil), do: "—"

  def format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  @gib Float.pow(1024.0, 3)
  @tib Float.pow(1024.0, 4)

  def format_bytes(bytes) when bytes >= @tib do
    "#{Float.round(bytes / @tib, 1)} TiB"
  end

  def format_bytes(bytes) do
    "#{Float.round(bytes / @gib, 1)} GiB"
  end

  # --- Pipeline Stage Display ---

  def stage_dot_class(:idle), do: "bg-base-content/20"
  def stage_dot_class(:active), do: "bg-success"
  def stage_dot_class(:saturated), do: "bg-warning"
  def stage_dot_class(:erroring), do: "bg-error"

  def stage_text_class(:idle), do: "text-base-content/60"
  def stage_text_class(:active), do: "text-success"
  def stage_text_class(:saturated), do: "text-warning"
  def stage_text_class(:erroring), do: "text-error"

  def stage_status_label(:idle), do: "idle"
  def stage_status_label(:active), do: "active"
  def stage_status_label(:saturated), do: "saturated"
  def stage_status_label(:erroring), do: "erroring"

  def stage_display_name(:parse), do: "Parse Media Path"
  def stage_display_name(:search), do: "Match on TMDB"
  def stage_display_name(:fetch_metadata), do: "Enrich Metadata"
  def stage_display_name(:ingest), do: "Add to Library"

  # --- Directory Status ---

  def resolve_dir_status(health, watcher_statuses) do
    cond do
      not health.dir_exists -> :missing
      watcher = Enum.find(watcher_statuses, &(&1.dir == health.dir)) -> watcher.state
      true -> :stopped
    end
  end

  def dir_status_label(:missing), do: "missing"
  def dir_status_label(:stopped), do: "not watched"
  def dir_status_label(:watching), do: "watching"
  def dir_status_label(:initializing), do: "initializing"
  def dir_status_label(_), do: "unavailable"

  def dir_status_text_class(:missing), do: "text-error"
  def dir_status_text_class(:stopped), do: "text-warning"
  def dir_status_text_class(:watching), do: "text-success"
  def dir_status_text_class(:initializing), do: "text-warning"
  def dir_status_text_class(_), do: "text-error"

  # --- Playback Display ---

  def playback_text_class(:idle), do: "text-base-content/60"
  def playback_text_class(:playing), do: "text-success"
  def playback_text_class(:paused), do: "text-warning"
  def playback_text_class(_), do: "text-info"

  def playback_progress_class(:playing), do: "progress-success"
  def playback_progress_class(:paused), do: "progress-warning"
  def playback_progress_class(_), do: "progress-info"

  def playback_border_class(:playing), do: "border-success"
  def playback_border_class(:paused), do: "border-warning"
  def playback_border_class(_), do: "border-base-content/20"

  # --- Usage Display ---

  def usage_progress_class(percent) when percent >= 90, do: "progress-error"
  def usage_progress_class(percent) when percent >= 75, do: "progress-warning"
  def usage_progress_class(_percent), do: "progress-success"

  def usage_text_class(percent) when percent >= 90, do: "text-error"
  def usage_text_class(percent) when percent >= 75, do: "text-warning"
  def usage_text_class(_percent), do: "text-success"
end
