defmodule MediaCentaurWeb.LibraryProgress do
  @moduledoc """
  Pure helpers for watch-progress rendering — resume buttons, completion
  percentages, FK resolution for progress lookups, and the merge logic
  the LiveView uses to fold in incoming `:progress_changed` events
  without rebuilding the full entries list.
  """

  alias MediaCentaur.Library.{EpisodeList, MovieList}

  # --- Progress fraction + completion ---

  def compute_progress_fraction(nil), do: 0

  def compute_progress_fraction(%{
        episode_position_seconds: position,
        episode_duration_seconds: duration
      })
      when duration > 0 do
    Float.round(position / duration * 100, 1)
  end

  def compute_progress_fraction(_), do: 0

  @doc """
  Formats the completion percentage of a progress record for display.
  Returns `"42%"` or `"unknown"` when the duration is missing or zero.
  """
  @spec completion_percentage(map() | nil) :: String.t()
  def completion_percentage(%{position_seconds: position, duration_seconds: duration})
      when is_number(duration) and duration > 0 and is_number(position) do
    "#{trunc(Float.round(position / duration * 100, 0))}%"
  end

  def completion_percentage(_), do: "unknown"

  # --- Resume button labels ---

  def format_resume_parts(nil, _entry), do: {nil, nil}

  def format_resume_parts(%{"action" => "resume"} = resume, entry) do
    label =
      case resume do
        %{"seasonNumber" => season, "episodeNumber" => episode} ->
          "Season #{season} episode #{episode}"

        _ ->
          nil
      end

    time_remaining =
      case resume do
        %{"positionSeconds" => position, "durationSeconds" => duration}
        when is_number(duration) and duration > 0 ->
          remaining = max(trunc(duration - position), 0)
          MediaCentaurWeb.LibraryFormatters.format_human_duration(remaining) <> " remaining"

        _ ->
          episodes_remaining_label(entry.entity, entry.progress_records)
      end

    {label, time_remaining}
  end

  def format_resume_parts(%{"action" => "begin"} = resume, entry) do
    label =
      case resume do
        %{"seasonNumber" => season, "episodeNumber" => episode} ->
          "Play season #{season} episode #{episode}"

        _ ->
          "Play"
      end

    {label, episodes_remaining_label(entry.entity, entry.progress_records)}
  end

  def format_resume_parts(_resume, _entry), do: {nil, nil}

  def episodes_remaining_label(entity, progress_records) do
    total =
      case entity.type do
        :tv_series -> length(EpisodeList.list_available(entity))
        :movie_series -> length(MovieList.list_available(entity))
        _ -> 0
      end

    completed = Enum.count(progress_records, & &1.completed)
    remaining = total - completed

    case remaining do
      n when n > 1 -> "#{n} episodes remaining"
      1 -> "1 episode remaining"
      _ -> nil
    end
  end

  # --- Entry status ---

  def in_progress?(%{progress: nil}), do: false

  def in_progress?(%{progress: summary}) do
    in_progress_summary?(summary)
  end

  @doc """
  Variant for callers that already hold a `ProgressSummary`-shaped map
  directly (rather than the rich `%{entity:, progress:}` entry shape).
  Used by the LibraryLive grid path after Library Schema v2 Phase 3.1
  — `progress_by_id[entry.id]` returns the summary, not a wrapped
  entry.
  """
  @spec in_progress_summary?(map() | nil) :: boolean()
  def in_progress_summary?(nil), do: false

  def in_progress_summary?(summary) when is_map(summary) do
    summary.episodes_completed < summary.episodes_total
  end

  # --- Progress record merging ---

  def merge_progress_record(records, nil), do: records

  def merge_progress_record(records, changed) do
    key = progress_record_key(changed)

    case Enum.find_index(records, &(progress_record_key(&1) == key)) do
      nil -> records ++ [changed]
      index -> List.replace_at(records, index, changed)
    end
  end

  defp progress_record_key(record) do
    # WatchProgress is keyed solely by `playable_item_id` since Library
    # Schema v2 Phase 2 Task C — the unique constraint on
    # `playable_item_id` makes that the natural identity. Extras flow
    # through `merge_extra_progress/2`, so we don't need a cross-stream
    # tiebreak here.
    Map.get(record, :playable_item_id)
  end

  def merge_extra_progress(records, nil), do: records

  def merge_extra_progress(records, changed) do
    case Enum.find_index(records, &(&1.extra_id == changed.extra_id)) do
      nil -> [changed | records]
      index -> List.replace_at(records, index, changed)
    end
  end
end
