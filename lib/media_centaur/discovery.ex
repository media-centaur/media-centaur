defmodule MediaCentaur.Discovery do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TmdbArtwork],
    exports: [WatchlistItem, Events, Events.ItemAdded, Events.ItemRemoved]

  @moduledoc """
  Bounded context for discovery: the local watchlist — title-level
  "I want to watch this" intent — and, in later iterations, the candidate
  sources that feed it (TMDB discover, list import, friend recommendations).

  Accepts plain attrs at the boundary (cross-context composition is plain
  data). Scheduled convergence: when this context grows its first
  TMDB-calling source, TMDB title search and a neutral title struct move
  from `ReleaseTracking` into `MediaCentaur.TMDB` and both contexts
  consume them (see the unification notes in
  docs/superpowers/plans/2026-08-18-watchlist-foundation.md).
  """

  import Ecto.Query

  alias MediaCentaur.Discovery.{Events, WatchlistItem}
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to watchlist update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.discovery_updates())

  @doc """
  Adds a title to the watchlist. Idempotent — re-adding an existing
  `(tmdb_id, media_type)` returns the existing item unchanged, including
  when a concurrent insert wins the race (unique-constraint branch).
  """
  def add_to_watchlist(attrs) do
    case get_item(attrs[:tmdb_id], attrs[:media_type]) do
      %WatchlistItem{} = existing ->
        {:ok, existing}

      nil ->
        attrs
        |> WatchlistItem.create_changeset()
        |> Repo.insert()
        |> case do
          {:ok, item} ->
            ensure_artwork_async(item)

            Events.broadcast(%Events.ItemAdded{
              item_id: item.id,
              tmdb_id: item.tmdb_id,
              media_type: item.media_type
            })

            {:ok, item}

          {:error, %Ecto.Changeset{errors: errors} = changeset} ->
            # Concurrent add won the race — the unique constraint fired;
            # re-fetch so idempotency holds under contention too.
            if Keyword.has_key?(errors, :tmdb_id),
              do: {:ok, get_item(attrs[:tmdb_id], attrs[:media_type])},
              else: {:error, changeset}
        end
    end
  end

  @doc "Removes a title from the watchlist. Absent refs are a no-op."
  @spec remove_from_watchlist(integer(), :movie | :tv_series) :: :ok
  def remove_from_watchlist(tmdb_id, media_type) do
    case get_item(tmdb_id, media_type) do
      nil ->
        :ok

      item ->
        Repo.delete(item)
        Events.broadcast(%Events.ItemRemoved{tmdb_id: tmdb_id, media_type: media_type})
        :ok
    end
  end

  @doc """
  All watchlist items, newest first, each with the owning library
  container's id (nil when the library doesn't know the title) — derived
  live via `Library.ExternalIds.tmdb_owners/1`, never stored.
  """
  @spec list_watchlist() :: [%{item: WatchlistItem.t(), library_owner_id: Ecto.UUID.t() | nil}]
  def list_watchlist do
    items = Repo.all(from(w in WatchlistItem, order_by: [desc: w.inserted_at]))
    owners = ExternalIds.tmdb_owners(Enum.map(items, &{&1.tmdb_id, &1.media_type}))

    Enum.map(items, fn item ->
      %{item: item, library_owner_id: Map.get(owners, {item.tmdb_id, item.media_type})}
    end)
  end

  @spec on_watchlist?(integer(), :movie | :tv_series) :: boolean()
  def on_watchlist?(tmdb_id, media_type), do: not is_nil(get_item(tmdb_id, media_type))

  @doc "The `{tmdb_id, media_type}` ref set — bulk decoration for search rows."
  @spec watchlisted_refs() :: MapSet.t({integer(), :movie | :tv_series})
  def watchlisted_refs do
    MapSet.new(Repo.all(from(w in WatchlistItem, select: {w.tmdb_id, w.media_type})))
  end

  defp get_item(tmdb_id, media_type) do
    Repo.one(from(w in WatchlistItem, where: w.tmdb_id == ^tmdb_id and w.media_type == ^media_type))
  end

  # Watchlist items persist, so their artwork moves from TMDB-hotlink to
  # the local referenced tier. Network — context-layer task (ADR-049).
  defp ensure_artwork_async(item) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      TmdbArtwork.ensure(item.media_type, item.tmdb_id)
    end)

    :ok
  end
end
