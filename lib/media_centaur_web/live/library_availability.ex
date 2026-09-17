defmodule MediaCentaurWeb.LibraryAvailability do
  @moduledoc """
  Pure helpers for computing storage-availability state shown to the user —
  per-card lookup map, total offline count, and the offline banner summary.

  Operates on lists of `MediaCentaur.Library.Views.BrowseItem` structs
  produced by the Browse projection (Library Schema v2 Phase 3.1). The
  rich `entity.watched_files` preload is no longer available at this
  layer; availability lookups go through the bulk
  `Library.Availability.available_for_ids/1` context function instead.
  """

  alias MediaCentaur.Library.Availability

  @doc """
  Builds `%{entity_id => available?}` for the template's per-card
  lookups. Single bulk DB query under the hood (Phase 3.1) so a full
  grid mount costs a bounded number of queries regardless of catalog
  size.
  """
  @spec availability_map([map()]) :: %{String.t() => boolean()}
  def availability_map(entries) do
    Availability.available_for_ids(Enum.map(entries, & &1.id))
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
