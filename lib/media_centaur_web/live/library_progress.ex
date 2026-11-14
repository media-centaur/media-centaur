defmodule MediaCentaurWeb.LibraryProgress do
  @moduledoc """
  Pure helpers for watch-progress rendering — completion percentages and
  the merge logic
  the LiveView uses to fold in incoming `:progress_changed` events
  without rebuilding the full entries list.
  """

  # --- Completion percentage ---

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
    # A page holds one profile's records, within which `playable_item_id`
    # is unique (`(profile_id, playable_item_id)`, ADR-078) — the natural
    # identity for the merge. Extras flow through `merge_extra_progress/2`,
    # so we don't need a cross-stream tiebreak here.
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
