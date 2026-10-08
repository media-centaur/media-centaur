defmodule MediaCentaur.Profile.Suites.WatchHistorySummarySuite do
  @moduledoc """
  Validates the projection vs. legacy DB query path for the
  WatchHistory dashboard summary (ADR-041). Compares cached and
  uncached read paths.

  Two inputs:

    * `warm-cache` — `Summary.refresh_cache/0` runs first, so
      `Views.summary/1` reads from `:persistent_term`.
    * `cold-fallback` — the `:persistent_term` key is erased, so
      `Views.summary/1` falls through to three live
      `WatchHistory.*` reads (stats + heatmap + three rewatch
      maps).

  Both scenarios read the owner profile's history (ADR-078).
  """
  @behaviour MediaCentaur.Profile.Suite

  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Views
  alias MediaCentaur.WatchHistory.Views.Summary

  @cache_key {Summary, :data}

  @impl true
  def name, do: "WatchHistory.Views.Summary"

  @impl true
  def inputs do
    %{
      "warm-cache" => fn -> Summary.refresh_cache() end,
      "cold-fallback" => fn -> :persistent_term.erase(@cache_key) end
    }
  end

  @impl true
  def scenarios do
    owner_id = MediaCentaur.Profiles.owner().id

    %{
      "Views.summary/1" => fn -> Views.summary(owner_id) end,
      "WatchHistory.stats/1 + heatmap + 3x rewatch_count_map" => fn ->
        %{
          stats: WatchHistory.stats(owner_id),
          heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type(owner_id),
          rewatch_counts: %{
            movie: WatchHistory.rewatch_count_map(owner_id, :movie),
            episode: WatchHistory.rewatch_count_map(owner_id, :episode),
            video_object: WatchHistory.rewatch_count_map(owner_id, :video_object)
          }
        }
      end
    }
  end
end
