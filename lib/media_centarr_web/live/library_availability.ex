defmodule MediaCentarrWeb.LibraryAvailability do
  @moduledoc """
  Pure helpers for computing storage-availability state shown to the user —
  per-card lookup map, total offline count, and the offline banner summary.
  """

  alias MediaCentarr.Library.Availability

  @doc """
  Counts entries whose backing storage is currently offline.

  Accepts an optional predicate for test injection; defaults to
  `Library.Availability.available?/1`, which is a persistent-term read.
  Computed once per entries/dir-status change rather than every render.
  """
  @spec unavailable_count(list(), (map() -> boolean())) :: non_neg_integer()
  def unavailable_count(entries, available_fn \\ &Availability.available?/1) do
    Enum.count(entries, fn entry -> not available_fn.(entry.entity) end)
  end

  @doc """
  Builds `%{entity_id => available?}` for the template's per-card lookups.

  Avoids calling `Library.Availability.available?/1` once per card on every
  render — each call digs into `entity.watched_files` to resolve the
  owning watch_dir, which is cheap individually but adds up across a full
  grid of poster cards.
  """
  @spec availability_map(list(), (map() -> boolean())) :: %{String.t() => boolean()}
  def availability_map(entries, available_fn \\ &Availability.available?/1) do
    Map.new(entries, fn entry -> {entry.entity.id, available_fn.(entry.entity)} end)
  end

  @doc """
  Builds the one-line summary shown in the `storage_offline_banner`.

  Takes the per-dir state map (from `Library.Availability.dir_status/0`)
  and a count of library entries currently unavailable. Returns a
  human-readable string or `nil` when no dir is offline.
  """
  @spec offline_summary(%{String.t() => atom()}, non_neg_integer()) :: String.t() | nil
  def offline_summary(dir_status, unavailable_count) do
    offline_dirs =
      dir_status
      |> Enum.filter(fn {_dir, state} -> state == :unavailable end)
      |> Enum.map(fn {dir, _} -> dir end)

    case offline_dirs do
      [] ->
        nil

      [dir] ->
        "#{dir} is offline — #{items_phrase(unavailable_count)} temporarily unavailable."

      dirs ->
        "#{length(dirs)} storage locations offline — #{items_phrase(unavailable_count)} temporarily unavailable."
    end
  end

  defp items_phrase(1), do: "1 item"
  defp items_phrase(n), do: "#{n} items"
end
