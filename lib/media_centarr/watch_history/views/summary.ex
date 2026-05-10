defmodule MediaCentarr.WatchHistory.Views.Summary do
  @moduledoc """
  `:persistent_term`-backed projection of the History page's aggregate
  read paths (ADR-041). Bundles `WatchHistory.stats/0`,
  `heatmap_cells_by_type/0`, and the three per-type
  `rewatch_count_map/1` calls into one snapshot the LiveView reads in
  a single lookup at render time.

  `:persistent_term` flavour because the payload is small,
  mostly-read, and hot — exactly the shape that benefits from
  byte-code-inlined reads. Each refresh costs all readers a fresh
  copy of the payload; the History page is the only reader and
  refreshes are event-driven (a handful per active day at most), so
  the cost is negligible.

  ## Refresh triggers

  Subscribes to `watch_history:events`:

    * `{:watch_event_created, _}` — a new completion landed.
    * `{:watch_event_deleted, _}` — the user removed a row from
      `/history`.

  ## Read fallback

  `read/0` returns a freshly-computed `SummaryData` when
  `:persistent_term` is unset — preserves identical behaviour in test
  mode (where no Cache.Worker runs) and during the brief boot window
  before the first refresh.
  """
  @behaviour MediaCentarr.Cache

  alias MediaCentarr.Topics
  alias MediaCentarr.WatchHistory
  alias MediaCentarr.WatchHistory.Views.SummaryData

  @cache_key {__MODULE__, :data}

  @impl MediaCentarr.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.watch_history_events())
  end

  @impl MediaCentarr.Cache
  def relevant?({:watch_event_created, _}), do: true
  def relevant?({:watch_event_deleted, _}), do: true
  def relevant?(_), do: false

  @impl MediaCentarr.Cache
  def refresh_cache do
    :persistent_term.put(@cache_key, compute())

    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.watch_history_views(),
      {:watch_history_view_updated, :summary}
    )

    :ok
  end

  @doc """
  Read the cached snapshot, falling back to a fresh compute when
  `:persistent_term` is unset.
  """
  @spec read() :: SummaryData.t()
  def read do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> compute()
      data -> data
    end
  end

  defp compute do
    %SummaryData{
      stats: WatchHistory.stats(),
      heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type(),
      rewatch_counts: %{
        movie: WatchHistory.rewatch_count_map(:movie),
        episode: WatchHistory.rewatch_count_map(:episode),
        video_object: WatchHistory.rewatch_count_map(:video_object)
      }
    }
  end
end
