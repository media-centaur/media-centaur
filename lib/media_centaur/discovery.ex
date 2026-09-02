defmodule MediaCentaur.Discovery do
  use Boundary,
    deps: [MediaCentaur.Library, MediaCentaur.TmdbArtwork, MediaCentaur.TMDB],
    exports: [WatchlistItem, Events, Events.ItemAdded, Events.ItemRemoved]

  @moduledoc """
  Bounded context for discovery: the local watchlist — title-level
  "I want to watch this" intent — and, in later iterations, the candidate
  sources that feed it (TMDB discover, list import, friend recommendations).

  Accepts `MediaCentaur.TMDB.Title` at the boundary — the app-wide title
  value every candidate source produces (converged 2026-09-02; see
  docs/superpowers/specs/2026-09-02-friends-recommendations-design.md).
  """

  import Ecto.Query

  alias MediaCentaur.Discovery.{Events, WatchlistItem}
  alias MediaCentaur.Library.ExternalIds
  alias MediaCentaur.Repo
  alias MediaCentaur.TmdbArtwork
  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.Topics

  @doc "Subscribe the caller to watchlist update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe, do: Topics.subscribe(Topics.discovery_updates())

  @doc """
  Adds a title to the watchlist. `attrs` may carry `:source`, `:note`
  and — for a `:friend`-sourced item — `:recommendation_id`. Idempotent — re-adding an existing `(tmdb_id, media_type)`
  returns the existing item unchanged, including when a concurrent
  insert wins the race (unique-constraint branch).
  """
  @spec add_to_watchlist(Title.t(), map()) :: {:ok, WatchlistItem.t()} | {:error, Ecto.Changeset.t()}
  def add_to_watchlist(%Title{} = title, attrs \\ %{}) do
    case get_item(title.tmdb_id, title.media_type) do
      %WatchlistItem{} = existing ->
        {:ok, existing}

      nil ->
        title
        |> WatchlistItem.create_changeset(attrs)
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
            # Concurrent add won the race exactly when a unique constraint
            # fired (constraint metadata, not field name — a future
            # validation on :tmdb_id must not be mistaken for the race);
            # re-fetch so idempotency holds under contention too.
            unique_violation? =
              Enum.any?(errors, fn {_field, {_msg, meta}} -> meta[:constraint] == :unique end)

            if unique_violation?,
              do: {:ok, get_item(title.tmdb_id, title.media_type)},
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
