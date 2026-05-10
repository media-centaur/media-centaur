defmodule MediaCentarr.Profile.Suites.WatchHistorySummarySuite do
  @moduledoc """
  Validates the projection vs. legacy DB query path for the
  WatchHistory dashboard summary (ADR-041). Compares cached and
  uncached read paths.

  Two inputs:

    * `warm-cache` — `Summary.refresh_cache/0` runs first, so
      `Views.summary/0` reads from `:persistent_term`.
    * `cold-fallback` — the `:persistent_term` key is erased, so
      `Views.summary/0` falls through to three live
      `WatchHistory.*` reads (stats + heatmap + three rewatch
      maps).
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.WatchHistory
  alias MediaCentarr.WatchHistory.Views
  alias MediaCentarr.WatchHistory.Views.Summary

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
    %{
      "Views.summary/0" => fn -> Views.summary() end,
      "WatchHistory.stats/0 + heatmap + 3x rewatch_count_map" => fn ->
        %{
          stats: WatchHistory.stats(),
          heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type(),
          rewatch_counts: %{
            movie: WatchHistory.rewatch_count_map(:movie),
            episode: WatchHistory.rewatch_count_map(:episode),
            video_object: WatchHistory.rewatch_count_map(:video_object)
          }
        }
      end
    }
  end
end

defmodule MediaCentarr.Profile.Suites.WatchHistorySummaryRefreshSuite do
  @moduledoc """
  Standalone refresh-cost measurement for the WatchHistory summary
  projection, isolated from the read-path suite.
  """
  @behaviour MediaCentarr.Profile.Suite

  alias MediaCentarr.WatchHistory.Views.Summary

  @impl true
  def name, do: "WatchHistory.Views.Summary.refresh_cache/0"

  @impl true
  def inputs, do: %{}

  @impl true
  def scenarios do
    %{
      "Summary.refresh_cache/0" => fn -> Summary.refresh_cache() end
    }
  end
end
