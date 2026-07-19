defmodule MediaCentaur.ReleaseTracking.Views.ComingUp do
  @moduledoc """
  ETS-backed projection of Coming Up rows (ADR-041).

  Mirrors the output of `MediaCentaur.ReleaseTracking.list_releases_between/3`
  into a named ETS table holding `ComingUpItem` structs keyed by
  display rank. Reads bypass the GenServer entirely — see
  `MediaCentaur.ReleaseTracking.Views.coming_up/3`.

  ## Date window

  The projection caches a wide window (`today..today+@horizon_days`)
  computed at refresh time. Reads filter by the caller's requested
  window, so the LiveView's "next 90 days" view is satisfied by an
  in-memory scan of cached items rather than a fresh DB query.

  Midnight rollover is bounded by the refresh cadence (event-driven),
  which mirrors the legacy LiveView behaviour: until a release-tracking
  event fires, the cached window edges are slightly stale. Acceptable
  for an event-driven domain where new releases trigger refresh.

  ## Refresh triggers

  Subscribes to release-tracking updates only:

    * `release_tracking:updates` — releases added/removed/changed
      (`releases_updated`, `item_removed`), plus the sweep tick
      (`tracking_sweep_completed`) as the midnight-rollover re-read
      signal (`released` is derived from `air_date`, so cached rows go
      stale at midnight with no broadcast).

  Grab status enrichment is intentionally NOT included in this
  projection. Acquisition has a hard dependency on ReleaseTracking;
  taking a back-dep here would form a cycle. Callers enrich at read
  time (HomeLive composes `Acquisition.statuses_for_releases/1` over
  the cached release list).

  ## Storage

    * `:release_tracking_view_coming_up` — `:ordered_set`, `:public`,
      `:read_concurrency, true`. Keyed by display rank.
  """
  @behaviour MediaCentaur.Cache

  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.ReleaseTracking.Views.ComingUpItem
  alias MediaCentaur.ReleaseTracking.Views.ComingUpItemRef
  alias MediaCentaur.Topics

  @table :release_tracking_view_coming_up
  @horizon_days 365
  @max_items 200

  @impl MediaCentaur.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.release_tracking_updates())
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:releases_updated, _}), do: true
  def relevant?({:item_removed, _, _}), do: true
  # `released` is derived from `air_date` on read, so cached rows silently
  # go stale at midnight (no broadcast fires when a date crosses today).
  # The sweep tick is the projection's re-read signal, bounding that
  # midnight-rollover staleness to the sweep cadence.
  def relevant?({:tracking_sweep_completed}), do: true
  def relevant?(_), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    ensure_table()

    today = Date.utc_today()
    to_date = Date.add(today, @horizon_days)

    items =
      today
      |> ReleaseTracking.list_releases_between(to_date, limit: @max_items)
      |> Enum.map(&to_view_model/1)

    rows = Enum.with_index(items, fn item, rank -> {rank, item} end)

    :ets.delete_all_objects(@table)
    :ets.insert(@table, rows)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      Topics.release_tracking_views(),
      {:release_tracking_view_updated, :coming_up}
    )

    :ok
  end

  @doc """
  Read the projection, filtered by the requested date window. Falls
  back to the underlying DB query when the ETS table is absent —
  covers test mode (Cache.Worker not started) and the brief window
  between boot and first refresh.
  """
  @spec read(Date.t(), Date.t(), keyword()) :: [ComingUpItem.t()]
  def read(from_date, to_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)

    case :ets.whereis(@table) do
      :undefined -> read_from_db(from_date, to_date, limit)
      _ref -> read_from_ets(from_date, to_date, limit)
    end
  end

  defp read_from_ets(from_date, to_date, limit) do
    @table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {rank, _item} -> rank end)
    |> Enum.map(fn {_rank, item} -> item end)
    |> Enum.filter(fn item ->
      Date.compare(item.air_date, from_date) != :lt and
        Date.compare(item.air_date, to_date) != :gt
    end)
    |> Enum.take(limit)
  end

  defp read_from_db(from_date, to_date, limit) do
    from_date
    |> ReleaseTracking.list_releases_between(to_date, limit: limit)
    |> Enum.map(&to_view_model/1)
  end

  defp to_view_model(row) do
    %ComingUpItem{
      item: %ComingUpItemRef{
        id: row.item.id,
        entity_id: Map.get(row.item, :entity_id),
        name: row.item.name,
        tmdb_id: Map.get(row.item, :tmdb_id),
        media_type: Map.get(row.item, :media_type)
      },
      air_date: row.air_date,
      season_number: Map.get(row, :season_number),
      episode_number: Map.get(row, :episode_number),
      status: Map.get(row, :status, :scheduled),
      backdrop_url: Map.get(row, :backdrop_url),
      logo_url: Map.get(row, :logo_url)
    }
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:ordered_set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  end
end
