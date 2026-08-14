defmodule MediaCentaur.ReleaseTracking do
  use Boundary,
    deps: [
      MediaCentaur.TMDB,
      MediaCentaur.Library,
      MediaCentaur.Retention,
      MediaCentaur.Search,
      MediaCentaur.Settings,
      MediaCentaur.TmdbArtwork
    ],
    exports: [
      Item,
      Release,
      TitleResult,
      Event,
      Want,
      Views,
      Views.ComingUp,
      Views.ComingUpItem,
      Views.ComingUpItemRef,
      UpcomingFeed,
      UpcomingFeed.Event,
      UpcomingFeed.Straggler
    ]

  @moduledoc """
  Bounded context for tracking upcoming movie and TV releases via TMDB.

  Fully isolated from the Library context — owns its own tables and images.
  TMDB-facing search and track-from-search onboarding live in the
  `ReleaseTracking.Acquisition` sub-module (this context delegates to it).
  """

  import Ecto.Query
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Repo

  alias MediaCentaur.ReleaseTracking.{
    Acquisition,
    Event,
    Helpers,
    Item,
    Release,
    Wants
  }

  alias MediaCentaur.TmdbArtwork

  alias MediaCentaur.Topics

  @doc "Subscribe the caller to release tracking update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.release_tracking_updates())
  end

  # --- Items ---

  def track_item(attrs) do
    Repo.insert(Item.create_changeset(attrs))
  end

  def track_item!(attrs) do
    Repo.insert!(Item.create_changeset(attrs))
  end

  def ignore_item(%Item{} = item) do
    Repo.update(Item.update_changeset(item, %{status: :ignored}))
  end

  def watch_item(%Item{} = item) do
    Repo.update(Item.update_changeset(item, %{status: :watching}))
  end

  def update_item(%Item{} = item, attrs) do
    Repo.update(Item.update_changeset(item, attrs))
  end

  @doc """
  Updates per-item auto-grab preferences and broadcasts `:releases_updated`
  so subscribed LiveViews refresh.

  `attrs` may include `:auto_grab_mode`, `:min_quality`, `:max_quality`,
  `:quality_4k_patience_hours`, `:prefer_season_packs`. Validation lives
  on `Item.auto_grab_changeset/2`.
  """
  def update_auto_grab(%Item{} = item, attrs) do
    case Repo.update(Item.auto_grab_changeset(item, attrs)) do
      {:ok, updated} ->
        broadcast_releases_updated([updated.id])
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  def get_item(id), do: Repo.get(Item, id)

  @doc """
  Nils the `(library_container_type, library_container_id)` link on every
  item pointing at one of `container_ids`. Returns the number of items
  detached.

  Called when a library container is cascade-destroyed (the Refresher
  reacts to `:containers_deleted`): the container reference has no FK, so
  without this the item would dangle against a deleted UUID forever.
  Tracking itself is intentionally kept — the user still follows the
  title, and auto-tracking re-links the item if the entity returns.
  """
  @spec detach_library_containers([Ecto.UUID.t()]) :: non_neg_integer()
  def detach_library_containers([]), do: 0

  def detach_library_containers(container_ids) when is_list(container_ids) do
    item_ids =
      Repo.all(from(i in Item, where: i.library_container_id in ^container_ids, select: i.id))

    case item_ids do
      [] ->
        0

      item_ids ->
        {count, _} =
          Repo.update_all(
            from(i in Item, where: i.id in ^item_ids),
            set: [library_container_id: nil, library_container_type: nil]
          )

        broadcast_releases_updated(item_ids)
        count
    end
  end

  def get_item_by_tmdb(tmdb_id, media_type) do
    Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type)
  end

  # Artwork is deliberately NOT removed here: untracking releases the
  # item's hold, and the TmdbArtwork sweep ages the entry out after its
  # TTL — re-tracking within the window finds the artwork warm.
  def delete_item(%Item{} = item) do
    item_id = item.id
    tmdb_id = to_string(item.tmdb_id)
    tmdb_type = tmdb_type_for(item.media_type)
    result = Repo.delete(item)
    broadcast_releases_updated([item_id])
    broadcast_item_removed(tmdb_id, tmdb_type)
    result
  end

  @doc """
  Closes out movie tracking for any newly-arrived library Movie. Looks
  up the TMDB ids on the given library entities and deletes matching
  `:movie` tracking items, writing a `:stopped_tracking` audit event
  per removal.

  TV series tracking is intentionally untouched — episodic content
  keeps releasing. Movie *collection* tracking is unaffected too:
  collection ids and movie ids live in different TMDB namespaces and
  will not collide.
  """
  @spec complete_movie_tracking_for([Ecto.UUID.t()]) :: :ok
  def complete_movie_tracking_for([]), do: :ok

  def complete_movie_tracking_for(entity_ids) when is_list(entity_ids) do
    tmdb_ids =
      entity_ids
      |> MediaCentaur.Library.ExternalIds.tmdb_ids_for_movies()
      |> Enum.flat_map(fn {_movie_id, tmdb_id_str} ->
        case Integer.parse(tmdb_id_str) do
          {int, ""} -> [int]
          _ -> []
        end
      end)

    case tmdb_ids do
      [] ->
        :ok

      ids ->
        items =
          Repo.all(
            from(i in Item,
              where: i.media_type == :movie and i.tmdb_id in ^ids
            )
          )

        Enum.each(items, &complete_tracking_for_item/1)
        :ok
    end
  end

  defp complete_tracking_for_item(%Item{} = item) do
    create_event!(%{
      item_id: item.id,
      item_name: item.name,
      event_type: :stopped_tracking,
      description: "#{item.name} is now in your library"
    })

    delete_item(item)
  end

  defp broadcast_item_removed(tmdb_id, tmdb_type) do
    Topics.publish(
      MediaCentaur.Topics.release_tracking_updates(),
      {:item_removed, tmdb_id, tmdb_type}
    )
  end

  @doc """
  Finds the highest season/episode pair for a TV series in the library.
  Returns `{season_number, episode_number}`, or `{0, 0}` if the series has
  no episodes (or `tv_series_id` is nil). Used by the Upcoming page
  to compute "next up" markers against the user's library state.
  """
  @spec find_last_library_episode(tv_series_id :: Ecto.UUID.t() | nil) ::
          {non_neg_integer(), non_neg_integer()}
  defdelegate find_last_library_episode(tv_series_id), to: Helpers

  def list_watching_items do
    Repo.all(
      from(i in Item, where: i.status == :watching, order_by: [asc: i.name], preload: [:releases])
    )
  end

  def list_all_items do
    Repo.all(from(i in Item, order_by: [asc: i.name], preload: [:releases]))
  end

  def tracking_status({tmdb_id, media_type}) do
    case Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type) do
      nil -> nil
      item -> item.status
    end
  end

  @doc "Broadcasts a `{:releases_updated, item_ids}` event to subscribers."
  def broadcast_releases_updated(item_ids) do
    Topics.publish(
      MediaCentaur.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end

  # --- Search & track-from-search (TMDB acquisition) ---
  #
  # Implementation lives in `ReleaseTracking.Acquisition`; these thin
  # delegators keep the context's public API stable for callers.

  @doc "See `MediaCentaur.ReleaseTracking.Acquisition.search_tmdb/1`."
  def search_tmdb(query), do: Acquisition.search_tmdb(query)

  @doc "See `MediaCentaur.ReleaseTracking.Acquisition.track_from_search/2`."
  def track_from_search(result, opts \\ %{}), do: Acquisition.track_from_search(result, opts)

  @doc "See `MediaCentaur.ReleaseTracking.Acquisition.track_from_search_async/2`."
  def track_from_search_async(result, opts \\ %{}), do: Acquisition.track_from_search_async(result, opts)

  # --- Releases ---

  def create_release(attrs) do
    Repo.insert(Release.create_changeset(attrs))
  end

  def create_release!(attrs) do
    Repo.insert!(Release.create_changeset(attrs))
  end

  @doc """
  Persists one episode/series release row for `item` from a release map,
  writing the full shape — including `release_type` and `part_tmdb_id`.
  Every TV-side persistence path (initial scan, refresh, auto-track) routes
  through this so the Differ's keys stay stable across refreshes; dropping
  either field churns the calendar. Movie collections use
  `persist_movie_releases/2`. `released` is not stored — it derives from
  `air_date` on read (`Release.released?/2`).
  """
  def persist_release!(%Item{} = item, release) do
    create_release!(%{
      item_id: item.id,
      air_date: release[:air_date],
      title: release[:title],
      season_number: release[:season_number],
      episode_number: release[:episode_number],
      release_type: release[:release_type],
      part_tmdb_id: release[:part_tmdb_id]
    })
  end

  @doc """
  Persists one movie release row. Movie counterpart to `persist_release!/2`
  (used for collection parts). `released` is derived from `air_date` on read.
  """
  def persist_movie_release!(%Item{} = item, release) do
    create_release!(%{
      item_id: item.id,
      air_date: release.air_date,
      title: release.title,
      release_type: release.release_type,
      part_tmdb_id: item.tmdb_id
    })
  end

  @doc """
  Atomically replace ALL of an item's releases (wholesale delete + re-insert
  inside a transaction). This is the single owner of the "an item's releases
  are rebuilt as a set" invariant — every (re)build path (refresh, auto-track,
  scan, track-from-search) routes through it, so a delete that races a concurrent
  rebuild can't interleave its insert and leave duplicates. The unique index
  `release_tracking_releases_identity_index` is the structural backstop.

  `persister` is the per-release inserter: `&persist_release!/2` (TV) or
  `&persist_movie_release!/2` (movies).
  """
  def replace_releases!(%Item{} = item, releases, persister) when is_function(persister, 2) do
    {:ok, _} =
      Repo.transaction(fn ->
        delete_releases_for_item(item.id)
        Enum.each(releases, &persister.(item, &1))
      end)

    :ok
  end

  # 24-hour window for keeping recently-completed releases visible on the
  # "Now Available" section so the user sees the success transition instead
  # of the row vanishing when the watcher imports the file.
  @recent_completion_hours 24

  def list_releases do
    cutoff = recently_completed_cutoff()

    all =
      Repo.all(
        from(r in Release,
          join: i in assoc(r, :item),
          where:
            i.status == :watching and
              (r.in_library == false or
                 (r.in_library == true and not is_nil(r.in_library_at) and
                    r.in_library_at >= ^cutoff)),
          order_by: [asc: r.air_date],
          preload: [:item]
        )
      )

    today = Date.utc_today()
    {released, upcoming} = Enum.split_with(all, &Release.released?(&1, today))

    %{upcoming: upcoming, released: released}
  end

  defp recently_completed_cutoff do
    DateTime.add(DateTime.utc_now(:second), -@recent_completion_hours * 3600, :second)
  end

  @doc """
  Dismiss a single release by deleting it. Also dismisses the matching
  open want — "dismiss this release" means stop wanting the unit, not
  just hide the calendar row.
  """
  def dismiss_release(release_id) do
    case Repo.get(Release, release_id) do
      nil ->
        {:error, :not_found}

      release ->
        Wants.dismiss_for_release(release)
        result = Repo.delete(release)
        broadcast_releases_updated([release.item_id])
        result
    end
  end

  def list_releases_for_item(item_id) do
    Repo.all(from(r in Release, where: r.item_id == ^item_id, order_by: [asc: r.air_date]))
  end

  @doc """
  Returns releases relevant for inline display on a Library entity's
  detail page: unaired releases (`air_date` in the future / absent) plus
  aired-but-not-in-library releases (`air_date <= today, in_library: false`).

  Excludes `in_library: true` rows — those belong on the Upcoming
  page's recently-completed lingering window, not the per-series
  detail. Filters to Items with `status: :watching` (matching
  `list_releases/0`'s gating), and to the requested `media_type`.

  Returns `[]` when no Item is linked to `library_container_id`.

  Ordered `(season_number ASC, episode_number ASC)` for deterministic
  rendering and trivial grouping by season at the call site.
  """
  @spec list_relevant_releases_for_library_container(Ecto.UUID.t(), :tv_series | :movie) ::
          [Release.t()]
  def list_relevant_releases_for_library_container(library_container_id, media_type) do
    today = Date.utc_today()

    Repo.all(
      from(r in Release,
        join: i in assoc(r, :item),
        # unaired (air_date in the future / absent), or aired but not yet
        # in the library — `released` is derived from `air_date` on read.
        where:
          i.library_container_id == ^library_container_id and
            i.media_type == ^media_type and
            i.status == :watching and
            (is_nil(r.air_date) or r.air_date > ^today or r.in_library == false),
        order_by: [asc: r.season_number, asc: r.episode_number]
      )
    )
  end

  defp delete_releases_for_item(item_id) do
    Repo.delete_all(from(r in Release, where: r.item_id == ^item_id))
  end

  # --- Wants (ADR-056 ledger) ---

  @doc "See `MediaCentaur.ReleaseTracking.Wants.sync_item/1`."
  defdelegate sync_wants(item), to: Wants, as: :sync_item

  @doc "See `MediaCentaur.ReleaseTracking.Wants.open_wants_for_item/1`."
  defdelegate open_wants_for_item(item_id), to: Wants

  @doc "See `MediaCentaur.ReleaseTracking.Wants.list_open_wants/0`."
  defdelegate list_open_wants(), to: Wants

  @doc "See `MediaCentaur.ReleaseTracking.Wants.dismiss_before/2`."
  defdelegate dismiss_wants_before(item, cutoff), to: Wants, as: :dismiss_before

  @doc "See `MediaCentaur.ReleaseTracking.Wants.mark_searched/2`."
  defdelegate mark_wants_searched(want_ids, searched_at), to: Wants, as: :mark_searched

  @doc "See `MediaCentaur.ReleaseTracking.Wants.dismiss_units/2`."
  defdelegate dismiss_want_units(item_id, unit_keys), to: Wants, as: :dismiss_units

  @doc "See `MediaCentaur.ReleaseTracking.Wants.open_gap_wants/2`."
  defdelegate open_gap_wants(item, unit_specs), to: Wants

  @doc "See `MediaCentaur.ReleaseTracking.Wants.open_summary/0`."
  defdelegate open_wants_summary(), to: Wants, as: :open_summary

  # --- Events ---

  def create_event(attrs) do
    Repo.insert(Event.create_changeset(attrs))
  end

  def create_event!(attrs) do
    Repo.insert!(Event.create_changeset(attrs))
  end

  def list_recent_events(limit \\ 20) do
    Repo.all(
      from(e in Event,
        order_by: [{:desc, e.inserted_at}, {:desc, fragment("rowid")}],
        limit: ^limit
      )
    )
  end

  @doc "Recent events for a single tracked item — the per-title activity feed on the Upcoming detail panel."
  def list_events_for_item(item_id, limit \\ 10) do
    Repo.all(
      from(e in Event,
        where: e.item_id == ^item_id,
        order_by: [{:desc, e.inserted_at}, {:desc, fragment("rowid")}],
        limit: ^limit
      )
    )
  end

  @doc """
  Deletes tracking events inserted before `cutoff`. Returns the number of
  rows removed. Used by the retention sweep — events intentionally outlive
  their item (`on_delete: :nilify_all`), so the time window is the only
  thing bounding this log.
  """
  @spec prune_events(DateTime.t()) :: non_neg_integer()
  def prune_events(%DateTime{} = cutoff) do
    {count, _} = Repo.delete_all(from(e in Event, where: e.inserted_at < ^cutoff))
    count
  end

  @doc """
  Boot-time one-shot: moves any legacy `images/tracking/{tmdb_id}/`
  artwork into `TmdbArtwork`'s typed layout, using the tracked items to
  resolve each id's media type (unmapped dirs are orphans and are
  deleted). Idempotent and self-retiring — a no-op once the legacy root
  is gone. Skipped under `:test` like the other boot fixups.
  """
  @spec migrate_artwork_layout_on_boot(atom()) :: :ok
  def migrate_artwork_layout_on_boot(:test), do: :ok

  def migrate_artwork_layout_on_boot(_env) do
    mapping =
      from(i in Item, select: {i.tmdb_id, i.media_type})
      |> Repo.all()
      |> Map.new(fn {id, type} -> {to_string(id), type} end)

    TmdbArtwork.migrate_legacy!(mapping)
  end

  # --- Bulk operations ---

  @doc """
  Mark releases as in_library for a given item.

  TV series: episodes at or before last_library_season/episode are in the library.
  Movies: all aired releases (`air_date <= today`) are marked (the library entity
  existing means the collection is tracked, and aired movies are available).
  """
  def mark_in_library_releases(%Item{media_type: :tv_series} = item) do
    season = item.last_library_season || 0
    episode = item.last_library_episode || 0

    if season > 0 do
      now = DateTime.utc_now(:second)

      # `where: r.in_library == false` makes the update idempotent — re-marking
      # an already-in-library row would otherwise re-bump in_library_at on
      # every refresh cycle, breaking the 24h linger window.
      {count, _} =
        Repo.update_all(
          from(r in Release,
            where: r.item_id == ^item.id and r.in_library == false,
            where:
              r.season_number < ^season or
                (r.season_number == ^season and r.episode_number <= ^episode)
          ),
          set: [in_library: true, in_library_at: now]
        )

      if count > 0, do: broadcast_releases_updated([item.id])
    end
  end

  # No linked library container → the movie isn't in the library, so nothing
  # is "in library" no matter how many digital dates have passed. Mirrors the
  # TV clause's `last_library_season > 0` guard. Without this, a merely-tracked
  # movie (status :watching, never imported) had its released digital row
  # flagged in_library on every refresh, painting "in your library" on the
  # upcoming page for a movie the user didn't own.
  def mark_in_library_releases(%Item{media_type: :movie, library_container_id: nil}), do: :ok

  def mark_in_library_releases(%Item{media_type: :movie} = item) do
    now = DateTime.utc_now(:second)
    today = Date.utc_today()
    acquirable_types = acquirable_release_types()

    {count, _} =
      Repo.update_all(
        from(r in Release,
          where:
            r.item_id == ^item.id and not is_nil(r.air_date) and r.air_date <= ^today and
              r.in_library == false and
              (is_nil(r.release_type) or r.release_type in ^acquirable_types)
        ),
        set: [in_library: true, in_library_at: now]
      )

    if count > 0, do: broadcast_releases_updated([item.id])
  end

  @doc """
  Whether a `release_type` represents a release the user can acquire on their
  own (digital file, physical disc, or back-compat untyped row). Theatrical
  releases are informational only — the date the movie hits theaters has
  nothing to do with downloads.

  Single source of truth so `mark_in_library_releases/1`, the want
  ledger (`Wants`), and any UI code that needs to classify a release
  type all agree.
  """
  @spec acquirable_release_type?(String.t() | nil) :: boolean()
  def acquirable_release_type?(nil), do: true
  def acquirable_release_type?(type) when is_binary(type), do: type in acquirable_release_types()

  defp acquirable_release_types, do: ["digital", "physical"]

  @doc """
  Translates a tracking-item `media_type` atom to the TMDB-standard
  string consumed by `MediaCentaur.Acquisition.Pursuits.Pursuit.tmdb_type`
  and `MediaCentaur.Search.QueryBuilder.build/1`.

  Inverse of the Ecto-stringified form (`"tv_series"`), which would
  break QueryBuilder downstream — every auto-grab caller that hands
  TV item structs to Acquisition MUST run them through this translator.
  """
  @spec tmdb_type_for(:tv_series | :movie) :: String.t()
  def tmdb_type_for(:tv_series), do: "tv"
  def tmdb_type_for(:movie), do: "movie"

  @doc """
  Resolves the best available logo URL for a tracking item.

  Prefers the paired Library entity's logo (most authoritative — it's the same
  asset that drives the rest of the library); falls back to the identity's
  `TmdbArtwork` cache entry (fetched from TMDB by the refresher for shows not
  yet imported); returns `nil` if neither is available.

  `library_logos` is the map returned by
  `MediaCentaur.Library.Images.logo_urls_for_entities/1`, batched by the caller so
  a single query covers many items.

  Single source of truth for "what logo should this card show?" — both
  `upcoming_live` and `list_releases_between/3` route through here so the
  precedence rule lives in exactly one place.
  """
  @spec logo_url_for_item(%Item{}, %{Ecto.UUID.t() => String.t()}) :: String.t() | nil
  def logo_url_for_item(%Item{} = item, library_logos) do
    cond do
      item.library_container_id && Map.get(library_logos, item.library_container_id) ->
        Map.get(library_logos, item.library_container_id)

      logo = TmdbArtwork.urls(item.media_type, item.tmdb_id).logo_url ->
        logo

      true ->
        nil
    end
  end

  @doc """
  List tracked releases with `air_date` between `from_date` and `to_date` (inclusive),
  for watching items only. Used by HomeLive's "Coming Up" digest.

  Returns plain maps in the shape:
    `%{item: %{id, entity_id, name, tmdb_id, media_type}, air_date, season_number, episode_number, status, backdrop_url, logo_url}`

  `entity_id` is the paired Library entity UUID (nil if the item is not yet
  in the library). `logo_url` is filled when the paired Library entity has a
  `logo` image, otherwise `nil`. `status` is `:scheduled` — callers may
  enrich this with live grab status from Acquisition.
  """
  @spec list_releases_between(Date.t(), Date.t(), keyword()) :: [map()]
  def list_releases_between(from_date, to_date, opts \\ []) do
    limit = Keyword.get(opts, :limit, 8)

    releases =
      Repo.all(
        from(release in Release,
          join: item in assoc(release, :item),
          where:
            item.status == :watching and
              not is_nil(release.air_date) and
              release.air_date >= ^from_date and
              release.air_date <= ^to_date,
          order_by: [asc: release.air_date, asc: release.season_number, asc: release.episode_number],
          limit: ^limit,
          preload: [item: item]
        )
      )

    logo_urls =
      releases
      |> Enum.flat_map(fn r ->
        if r.item.library_container_id,
          do: [{r.item.media_type, r.item.library_container_id}],
          else: []
      end)
      |> MediaCentaur.Library.Images.logo_urls_for_entities()

    Enum.map(releases, fn release ->
      backdrop_url = TmdbArtwork.urls(release.item.media_type, release.item.tmdb_id).backdrop_url

      logo_url = logo_url_for_item(release.item, logo_urls)

      %{
        item: %{
          id: release.item.id,
          entity_id: release.item.library_container_id,
          name: release.item.name,
          tmdb_id: release.item.tmdb_id,
          media_type: release.item.media_type
        },
        air_date: release.air_date,
        season_number: release.season_number,
        episode_number: release.episode_number,
        release_type: release.release_type,
        status: :scheduled,
        backdrop_url: backdrop_url,
        logo_url: logo_url
      }
    end)
  end
end
