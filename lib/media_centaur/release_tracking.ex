defmodule MediaCentaur.ReleaseTracking do
  use Boundary,
    deps: [
      MediaCentaur.TMDB,
      MediaCentaur.Discovery,
      MediaCentaur.Library,
      MediaCentaur.Retention,
      MediaCentaur.Search,
      MediaCentaur.Settings,
      MediaCentaur.TmdbArtwork
    ],
    exports: [
      Identity,
      Item,
      LibraryListener,
      Release,
      Event,
      Want,
      Views,
      Views.ComingUp,
      Views.ComingUpItem,
      Views.ComingUpItemRef,
      UpcomingFeed,
      UpcomingFeed.Event
    ]

  @moduledoc """
  Bounded context for tracking upcoming movie and TV releases via TMDB.

  Owns its own tables and images. Reads the library only through
  `MediaCentaur.Library.*` public functions, never its schemas — a
  tracked item points at a library container by id and type.
  A tracked title is derived from a person's rung, never authored:
  `set_rung/3` is the one write path, and `ReleaseTracking.Onboarding`
  builds the machinery a followed title needs.
  """

  import Ecto.Query

  alias MediaCentaur.Repo

  alias MediaCentaur.Discovery
  alias MediaCentaur.Library.ExternalIds

  alias MediaCentaur.ReleaseTracking.LibraryLinks

  alias MediaCentaur.Discovery.TitleIntent

  alias MediaCentaur.ReleaseTracking.{
    Event,
    Helpers,
    Item,
    Onboarding,
    Release,
    Wants
  }

  alias MediaCentaur.TMDB.Title
  alias MediaCentaur.TmdbArtwork

  alias MediaCentaur.Topics

  @doc "Subscribe the caller to release tracking update events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Topics.subscribe(Topics.release_tracking_updates())
  end

  # --- Items ---

  @doc """
  Creates a tracking item.

  Silent by design: a tracked title is derived machinery, not a person's
  act. The act is a person raising a rung, and `set_rung/3` announces
  that — the announcement belongs to the record the person authored, not
  to the machine it started.
  """
  @spec track_item(map()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def track_item(attrs) do
    Repo.insert(Item.create_changeset(attrs))
  end

  def update_item(%Item{} = item, attrs) do
    Repo.update(Item.update_changeset(item, attrs))
  end

  def get_item(id), do: Repo.get(Item, id)

  @doc """
  Drops the library reason from every item pointing at one of
  `container_ids`, then reconciles each. Returns the number of items
  whose link was nilled.

  Called when a library container is cascade-destroyed (`LibraryListener`
  reacts to `:containers_deleted`): the container reference has no FK, so
  without this the item would dangle against a deleted UUID forever.

  The reconcile is the point ([ADR-065]). The library reason is a
  *default* — the app tracked the title because you owned it — so it
  evaporates with the container, and a title left with no reason stops
  being tracked. A title a person armed has the watchlist reason and
  keeps going at the mode they set; a disarmed one keeps its disarm.
  Before ADR-065 this kept *every* item, so a deleted series went on
  grabbing whether or not anyone had asked.
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
        refs = Repo.all(from(i in Item, where: i.id in ^item_ids, select: {i.tmdb_id, i.media_type}))

        {count, _} =
          Repo.update_all(
            from(i in Item, where: i.id in ^item_ids),
            set: [library_container_id: nil, library_container_type: nil]
          )

        broadcast_releases_updated(item_ids)
        reconcile_refs(refs)
        count
    end
  end

  def get_item_by_tmdb(tmdb_id, media_type) do
    Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type)
  end

  @doc """
  Re-derives one title's machinery from the rung it sits at, dropping the
  tracked title when the rung no longer calls for one.

  `set_rung/3` derives on the way in, so this exists for the *other*
  direction — the library moving underneath a rung that has not changed:
  a film arriving (which completes it) or a container being deleted. It
  only ever drops, never creates, so it can be called freely from the
  library listener without racing a person's act.
  """
  @spec reconcile(integer(), :movie | :tv_series) :: :ok
  def reconcile(tmdb_id, media_type) do
    case get_item_by_tmdb(tmdb_id, media_type) do
      nil -> :ok
      item -> reconcile_item(item)
    end
  end

  @doc "Reconciles every title in `refs`, a list of `{tmdb_id, media_type}`."
  @spec reconcile_refs([{integer(), :movie | :tv_series}]) :: :ok
  def reconcile_refs(refs) when is_list(refs) do
    Enum.each(refs, fn {tmdb_id, media_type} -> reconcile(tmdb_id, media_type) end)
  end

  defp reconcile_item(%Item{} = item) do
    rung = Discovery.rung(item.tmdb_id, item.media_type)

    if TitleIntent.follows_releases?(rung) and not owned_film?(item) do
      :ok
    else
      delete_item(item)
      :ok
    end
  end

  # A single film in the library is complete — nothing left to release.
  defp owned_film?(%Item{media_type: :movie, tmdb_id: tmdb_id}),
    do: ExternalIds.tmdb_owners([{tmdb_id, :movie}]) != %{}

  defp owned_film?(%Item{}), do: false

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
  Everything release tracking does when library entities change
  (`LibraryListener` calls this for every `entities_changed`): it
  reconciles what a person already asked for against what the library now
  holds — `LibraryLinks.refresh_for/1` links a followed title to the
  container that arrived, and `complete_movie_tracking_for/1` closes out
  a film that has nothing left to release.

  It never starts following anything. A series appearing in the library
  is a fact about the library, not a request; only a person puts a title
  on the ladder (campaign `tracking-is-a-persons-act`). Both passes are
  database-only, so an import never waits on the network.
  """
  @spec library_entities_changed([Ecto.UUID.t()]) :: :ok
  def library_entities_changed([]), do: :ok

  def library_entities_changed(entity_ids) when is_list(entity_ids) do
    LibraryLinks.refresh_for(entity_ids)
    complete_movie_tracking_for(entity_ids)
    :ok
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

  @doc """
  Every tracked title. There is no inactive kind any more: a row exists
  exactly while a person's rung follows the title's releases, so the
  filter this used to carry has nothing left to exclude.
  """
  @spec list_all_items() :: [Item.t()]
  def list_all_items do
    Repo.all(from(i in Item, order_by: [asc: i.name], preload: [:releases]))
  end

  @doc """
  The `{tmdb_id, media_type}` ref set of every tracked item — bulk
  decoration for title rows (the Tracked marker on search results).
  """
  @spec tracked_refs() :: MapSet.t({integer(), :movie | :tv_series})
  def tracked_refs do
    MapSet.new(Repo.all(from(i in Item, select: {i.tmdb_id, i.media_type})))
  end

  @doc "Broadcasts a `{:releases_updated, item_ids}` event to subscribers."
  def broadcast_releases_updated(item_ids) do
    Topics.publish(
      MediaCentaur.Topics.release_tracking_updates(),
      {:releases_updated, item_ids}
    )
  end

  @doc """
  Puts a title at `rung` — the one write path for a person's intent, and
  the only thing that creates or destroys a tracked title.

  `:off` forgets the title entirely: the record goes, and so does every
  piece of machinery derived from it. There is nothing to keep, because
  nothing but a person can put a title back on the ladder.

  Any other rung writes the record, then derives: at `:follow` and above
  the title needs a tracked title — its calendar, its wants, its artwork
  — and below `:follow` it does not, so the machinery is removed. A film
  already in the library is complete whatever the rung says; see
  `derive/2`.

  It lives here rather than in `Discovery` only because deriving needs to
  see both sides and the dependency runs this way — `Discovery` must stay
  free of tracking ([ADR-065] §6/§7).

  `attrs` may carry `:source`, `:note` and `:activity_id` (applied on
  creation), and `:start_season` / `:start_episode` to scope a first
  calendar fetch.
  """
  @spec set_rung(Title.t(), TitleIntent.rung() | :off, map()) ::
          {:ok, TitleIntent.t() | nil} | {:error, term()}
  def set_rung(title, rung, attrs \\ %{})

  def set_rung(%Title{} = title, :off, _attrs) do
    :ok = Discovery.forget(title.tmdb_id, title.media_type)
    :ok = drop_machinery(title.tmdb_id, title.media_type)
    {:ok, nil}
  end

  def set_rung(%Title{} = title, rung, attrs) do
    with {:ok, intent} <- Discovery.put_rung(title, rung, attrs),
         :ok <- derive(title, rung, attrs) do
      {:ok, intent}
    end
  end

  @doc """
  Fire-and-forget `set_rung/3`. Raising onto `:follow` or above fetches
  the calendar from TMDB, so it runs on a supervised context-layer task —
  it must complete regardless of the triggering LiveView's lifecycle
  (ADR-049). Subscribers catch up on `:releases_updated`.
  """
  @spec set_rung_async(Title.t(), TitleIntent.rung() | :off, map()) :: :ok
  def set_rung_async(%Title{} = title, rung, attrs \\ %{}) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> set_rung(title, rung, attrs) end)
    :ok
  end

  # The derivation rule, in one place. A tracked title exists exactly
  # when the person follows the title *and* there is a future to follow —
  # a single film already in the library is complete, so it has neither
  # calendar nor wants however high the rung sits. The rung is never
  # lowered to express that: the system does not move a person's intent.
  defp derive(%Title{} = title, rung, attrs) do
    cond do
      not TitleIntent.follows_releases?(rung) ->
        drop_machinery(title.tmdb_id, title.media_type)

      movie_in_library?(title) ->
        drop_machinery(title.tmdb_id, title.media_type)

      true ->
        with {:ok, _item} <- ensure_machinery(title, attrs), do: :ok
    end
  end

  defp ensure_machinery(%Title{} = title, attrs) do
    case get_item_by_tmdb(title.tmdb_id, title.media_type) do
      %Item{} = existing ->
        broadcast_releases_updated([existing.id])
        {:ok, existing}

      nil ->
        Onboarding.onboard(title, attrs)
    end
  end

  defp drop_machinery(tmdb_id, media_type) do
    case get_item_by_tmdb(tmdb_id, media_type) do
      nil -> :ok
      %Item{} = item -> with {:ok, _} <- delete_item(item), do: :ok
    end
  end

  defp movie_in_library?(%Title{media_type: :movie, tmdb_id: tmdb_id}),
    do: ExternalIds.tmdb_owners([{tmdb_id, :movie}]) != %{}

  defp movie_in_library?(%Title{}), do: false

  # --- Releases ---

  @doc """
  Inserts one release, returning `{:ok, release}` or `{:error, changeset}`.
  The non-raising pair to `create_release!/1`, which every production path
  uses — this one is how the identity unique index is asserted.
  """
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
            r.in_library == false or
              (r.in_library == true and not is_nil(r.in_library_at) and
                 r.in_library_at >= ^cutoff),
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
  detail. Filtered to the requested `media_type`; no mode filter, because
  a tracked title exists exactly while a person follows it.

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

  @doc "See `MediaCentaur.ReleaseTracking.Wants.mark_searched/2`."
  defdelegate mark_wants_searched(want_ids, searched_at), to: Wants, as: :mark_searched

  @doc "See `MediaCentaur.ReleaseTracking.Wants.dismiss_units/2`."
  defdelegate dismiss_want_units(item_id, unit_keys), to: Wants, as: :dismiss_units

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
