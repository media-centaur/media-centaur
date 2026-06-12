defmodule MediaCentaurWeb.StatusHelpers do
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

  Compares the progress's synthesised `playable_item.container_id`
  (plugged on by `MediaCentaur.Library.EntityShape.extract_progress/2`)
  against `now_playing.entity_id` — the container UUID
  `MpvSession.build_now_playing/1` emits. UUIDs are globally unique
  across container kinds, so the kind itself doesn't need to be
  compared.
  """
  def progress_matches_session?(record, now_playing) do
    case Map.get(record, :playable_item) do
      %{container_id: id} when not is_nil(id) ->
        id == now_playing[:entity_id]

      _ ->
        false
    end
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
    "#{MediaCentaurWeb.LibraryFormatters.format_human_duration(trunc(seconds))} remaining"
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
  @kib 1024.0
  @mib Float.pow(1024.0, 2)

  # Magnitude-aware: pick the largest unit that keeps the number readable, so a
  # sub-gigabyte value (e.g. an 8 MiB database) doesn't collapse to "0.0 GiB".
  # Three significant digits: one decimal below 10 units (where the fraction
  # carries real information), whole numbers above (where ".3" is noise).
  def format_bytes(bytes) when bytes >= @tib, do: "#{scaled(bytes / @tib)} TiB"
  def format_bytes(bytes) when bytes >= @gib, do: "#{scaled(bytes / @gib)} GiB"
  def format_bytes(bytes) when bytes >= @mib, do: "#{scaled(bytes / @mib)} MiB"
  def format_bytes(bytes) when bytes >= @kib, do: "#{scaled(bytes / @kib)} KiB"
  def format_bytes(bytes), do: "#{round(bytes)} B"

  defp scaled(value) when value < 10, do: Float.round(value, 1)
  defp scaled(value), do: round(value)

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

  # --- Watcher activity narrative ---

  @doc """
  Plain-language explanation of *why* a media directory is unavailable, from the
  `reason` tagged by `MediaCentaur.Watcher` at the transition. Turns a bare
  "unavailable" into something a curious user can act on (or wait out). Unknown
  or `nil` reasons fall back to a neutral line rather than leaking an atom.
  """
  @spec dir_failure_reason_label(atom() | nil) :: String.t()
  def dir_failure_reason_label(reason) when reason in [:unmounted, :never_mounted],
    do: "drive not mounted — waiting for it to come back"

  def dir_failure_reason_label(:inotify_missing), do: "inotify-tools not installed — live detection off"

  def dir_failure_reason_label(:backend_error), do: "file watcher couldn't start — check the directory"

  def dir_failure_reason_label(:inaccessible),
    do: "directory became inaccessible — waiting for it to come back"

  def dir_failure_reason_label(_other), do: "this directory is not being watched right now"

  @doc """
  Shapes the counts half of the last-scan line, e.g. `"1,432 files · 3 new"`,
  appending `" · N relinked"` only when the scan re-pointed moved files. The
  relative-time prefix is rendered separately in the template via
  `MediaCentaurWeb.LiveHelpers.time_ago/1`, keeping this helper pure and
  time-independent (ADR-030).
  """
  @spec format_scan_counts(%{
          total: non_neg_integer(),
          new: non_neg_integer(),
          relinked: non_neg_integer()
        }) ::
          String.t()
  def format_scan_counts(%{total: total, new: new_count, relinked: relinked}) do
    base = "#{format_count(total)} #{pluralize(total, "file")} · #{format_count(new_count)} new"
    if relinked > 0, do: base <> " · #{format_count(relinked)} relinked", else: base
  end

  @doc "Friendly noun for an enriched entity's kind, for the metadata-activity feed."
  @spec metadata_kind_label(atom()) :: String.t()
  def metadata_kind_label(:movie), do: "Movie"
  def metadata_kind_label(:tv_series), do: "Show"
  def metadata_kind_label(:movie_series), do: "Collection"
  def metadata_kind_label(:video_object), do: "Video"
  def metadata_kind_label(_other), do: "Item"

  @doc """
  Renders a recent-enrichment entry's title, appending `(year)` when known and
  falling back to `"Untitled"` rather than leaking a nil (e.g. an extra with no
  matched title).
  """
  @spec format_enriched_title(%{title: String.t() | nil, year: integer() | nil}) :: String.t()
  def format_enriched_title(%{title: nil}), do: "Untitled"
  def format_enriched_title(%{title: title, year: year}) when is_integer(year), do: "#{title} (#{year})"

  def format_enriched_title(%{title: title}), do: title

  defp pluralize(1, word), do: word
  defp pluralize(_count, word), do: word <> "s"

  # Thousands-separated integer for display (e.g. 1432 -> "1,432").
  defp format_count(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  # --- Playback Display ---

  def playback_text_class(:idle), do: "text-base-content/60"
  def playback_text_class(:playing), do: "text-success"
  def playback_text_class(:paused), do: "text-warning"
  def playback_text_class(_), do: "text-info"

  def playback_progress_class(:playing), do: "progress-success"
  def playback_progress_class(:paused), do: "progress-warning"
  def playback_progress_class(_), do: "progress-info"

  # --- Usage Display ---

  def usage_progress_class(percent) when percent >= 90, do: "progress-error"
  def usage_progress_class(percent) when percent >= 75, do: "progress-warning"
  def usage_progress_class(_percent), do: "progress-success"

  def usage_text_class(percent) when percent >= 90, do: "text-error"
  def usage_text_class(percent) when percent >= 75, do: "text-warning"
  def usage_text_class(_percent), do: "text-success"

  # --- Library overview (Status "Your library" section) ---

  @doc """
  Text-color class for a completeness-gap counter: amber when there is a gap
  to act on, muted otherwise. Color is reserved for signal — a zero count is
  not a problem and stays quiet.
  """
  @spec gap_count_class(non_neg_integer()) :: String.t()
  def gap_count_class(0), do: "text-base-content/40"
  def gap_count_class(count) when count > 0, do: "text-warning"

  @doc """
  Aggregates the per-dir at-risk summary into a single overview-card warning,
  counting only dirs that are currently offline (their TTL clock is ticking
  without the user's awareness — available dirs resolve themselves on the next
  scan). Returns `nil` when nothing is at risk, otherwise the total file count
  and the soonest purge horizon across the offline dirs.

  `dir_status` is `Library.Availability.dir_status/0`; an unknown dir is treated
  as offline so a warning is never silently suppressed. `now` and `ttl_days` are
  passed in so the helper stays pure and async-testable (ADR-030).
  """
  @spec summarize_at_risk(
          %{String.t() => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}},
          %{String.t() => atom()},
          DateTime.t(),
          non_neg_integer()
        ) :: nil | %{file_count: non_neg_integer(), purge_in_days: non_neg_integer()}
  def summarize_at_risk(at_risk_summary, dir_status, now, ttl_days) do
    offline =
      Enum.filter(at_risk_summary, fn {dir, _info} ->
        Map.get(dir_status, dir, :unavailable) == :unavailable
      end)

    case offline do
      [] ->
        nil

      entries ->
        file_count = entries |> Enum.map(fn {_dir, info} -> info.file_count end) |> Enum.sum()

        purge_in_days =
          entries
          |> Enum.map(fn {_dir, info} ->
            max(ttl_days - DateTime.diff(now, info.earliest_absent_since, :day), 0)
          end)
          |> Enum.min()

        %{file_count: file_count, purge_in_days: purge_in_days}
    end
  end

  # --- At-risk file warning (drive-offline durability surface) ---

  @doc """
  Shapes the per-dir at-risk row rendered by the directories component.
  Returns `nil` when nothing should be rendered for the dir, otherwise
  a view-model map.

  We deliberately suppress the row for dirs that are currently
  `:available`: their absent-file count is accurate but
  uninteresting (the watcher will resolve it on its next scan, no
  user action needed). The warning exists for offline dirs whose
  absence clock is ticking without the user's awareness.

  - `at_risk_summary` — the map returned by
    `MediaCentaur.Library.AbsenceSweeper.at_risk_summary/0`.
  - `dir_status` — the map returned by
    `MediaCentaur.Library.Availability.dir_status/0` (or `%{}` if not
    yet seeded — treat unknown dirs as offline so the warning isn't
    silently suppressed).
  - `now` and `ttl_days` — usually `DateTime.utc_now()` and the
    project's `:file_absence_ttl_days` config; passed in so the
    formatter is async-testable per ADR-030.
  """
  @spec format_at_risk_for_dir(
          String.t(),
          %{String.t() => %{file_count: non_neg_integer(), earliest_absent_since: DateTime.t()}},
          %{String.t() => atom()},
          DateTime.t(),
          non_neg_integer()
        ) ::
          nil
          | %{
              file_count: non_neg_integer(),
              earliest_absent_since: DateTime.t(),
              purge_in_days: non_neg_integer()
            }
  def format_at_risk_for_dir(dir, at_risk_summary, dir_status, now, ttl_days) do
    case Map.get(at_risk_summary, dir) do
      nil ->
        nil

      %{file_count: count, earliest_absent_since: earliest} ->
        if Map.get(dir_status, dir, :unavailable) == :unavailable do
          %{
            file_count: count,
            earliest_absent_since: earliest,
            purge_in_days: max(ttl_days - DateTime.diff(now, earliest, :day), 0)
          }
        end
    end
  end
end
