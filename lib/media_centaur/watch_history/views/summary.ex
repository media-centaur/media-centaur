defmodule MediaCentaur.WatchHistory.Views.Summary do
  @moduledoc """
  `:persistent_term`-backed projection of the History page's aggregate
  read paths (ADR-041). Bundles `WatchHistory.stats/1`,
  `heatmap_cells_by_type/1`, and the three per-type
  `rewatch_count_map/2` calls into one snapshot the LiveView reads in
  a single lookup at render time.

  Profile-keyed (ADR-078): one `SummaryData` per profile with an event,
  rebuilt whole on every refresh.

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

  `read/1` returns a freshly-computed `SummaryData` when
  `:persistent_term` is unset — preserves identical behaviour in test
  mode (where no Cache.Worker runs) and during the brief boot window
  before the first refresh — and for a profile the snapshot does not
  hold (no events yet).
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.Topics
  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Views.SummaryData

  # %{profile_id => SummaryData.t()} for every profile with an event.
  @cache_key {__MODULE__, :data}

  @impl MediaCentaur.Cache
  def subscribe do
    Topics.subscribe(Topics.watch_history_events())
  end

  @impl MediaCentaur.Cache
  def relevant?({:watch_event_created, _}), do: true
  def relevant?({:watch_event_deleted, _}), do: true
  def relevant?(_), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    snapshot = Map.new(WatchHistory.profile_ids_with_events(), &{&1, compute(&1)})
    :persistent_term.put(@cache_key, snapshot)

    Topics.publish(
      Topics.watch_history_views(),
      {:watch_history_view_updated, :summary}
    )

    :ok
  end

  @doc """
  One profile's snapshot. Falls back to a fresh compute when the term is
  unset (test mode, the boot window) or the profile has no events yet.
  """
  @spec read(Ecto.UUID.t()) :: SummaryData.t()
  def read(profile_id) when is_binary(profile_id) do
    case :persistent_term.get(@cache_key, :__unset) do
      :__unset -> compute(profile_id)
      snapshot -> Map.get_lazy(snapshot, profile_id, fn -> compute(profile_id) end)
    end
  end

  defp compute(profile_id) do
    %SummaryData{
      stats: WatchHistory.stats(profile_id),
      heatmap_cells_by_type: WatchHistory.heatmap_cells_by_type(profile_id),
      rewatch_counts: %{
        movie: WatchHistory.rewatch_count_map(profile_id, :movie),
        episode: WatchHistory.rewatch_count_map(profile_id, :episode),
        video_object: WatchHistory.rewatch_count_map(profile_id, :video_object)
      }
    }
  end
end
