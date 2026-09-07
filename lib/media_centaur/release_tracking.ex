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
      Item,
      LibraryListener,
      Reasons,
      WatchlistListener,
      Release,
      Event,
      Events,
      Events.TrackingStarted,
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

  Owns its own tables and images. Reads the library only through
  `MediaCentaur.Library.*` public functions, never its schemas — a
  tracked item points at a library container by id and type.
  TMDB-facing search and track-from-search onboarding live in the
  `ReleaseTracking.Acquisition` sub-module (this context delegates to it).
  """

  import Ecto.Query

  alias MediaCentaur.Repo

  alias MediaCentaur.Discovery
  alias MediaCentaur.Library.ExternalIds

  alias MediaCentaur.ReleaseTracking.{AutoTrackJob, LibraryLinks}

  alias MediaCentaur.ReleaseTracking.{
    Acquisition,
    Event,
    Events,
    Helpers,
    Item,
    Reasons,
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
  act ([ADR-065]). The act is arming a watchlist entry, and `Discovery`
  broadcasts `Events.TrackingStarted` for it — the announcement belongs
  to the record the person authored, not to the machine it started.
  """
  @spec track_item(map()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def track_item(attrs) do
    Repo.insert(Item.create_changeset(attrs))
  end

  @doc """
  Announces that a person started tracking `item`. Called by `Discovery`
  when an arming lands, never by the creation path.
  """
  @spec announce_tracking_started(Item.t()) :: :ok
  def announce_tracking_started(%Item{} = item) do
    Events.broadcast(%Events.TrackingStarted{
      item_id: item.id,
      title: Title.new!(%{tmdb_id: item.tmdb_id, media_type: item.media_type, name: item.name})
    })
  end

  @doc """
  Sets a tracked title's mode — the only way the mode ever moves, because
  nothing but a person may change it ([ADR-065]). Broadcasts
  `:releases_updated` so subscribed LiveViews refresh.
  """
  @spec set_tracking_mode(Item.t(), Item.tracking_mode()) ::
          {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def set_tracking_mode(%Item{} = item, mode) do
    with {:ok, updated} <- Repo.update(Item.update_changeset(item, %{tracking_mode: mode})) do
      broadcast_releases_updated([updated.id])
      {:ok, updated}
    end
  end

  def update_item(%Item{} = item, attrs) do
    Repo.update(Item.update_changeset(item, attrs))
  end

  @doc """
  Updates per-item automation preferences and broadcasts
  `:releases_updated` so subscribed LiveViews refresh.

  `attrs` may include `:tracking_mode`, `:min_quality`, `:max_quality`,
  `:quality_4k_patience_hours`, `:prefer_season_packs`. Validation lives
  on `Item.automation_changeset/2`.
  """
  def update_automation(%Item{} = item, attrs) do
    case Repo.update(Item.automation_changeset(item, attrs)) do
      {:ok, updated} ->
        broadcast_releases_updated([updated.id])
        {:ok, updated}

      {:error, changeset} ->
        {:error, changeset}
    end
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
  Reconciles one title's tracked-title row against its tracking reasons
  ([ADR-065]), dropping it when none holds.

  A tracked title is derived, not authored, so this is the only place its
  existence is decided. It never *creates* — the library scan and a
  person's arming do that, each seeding its own mode (`Reasons.seed_mode/1`).
  Reconcile only preserves or drops, which is why it can be called freely
  from either listener without racing a creation.

  [ADR-065]: `decisions/architecture/2026-09-07-065-tracking-reasons-and-the-derived-tracked-title.md`
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
    facts = %{
      mode: item.tracking_mode,
      media_type: item.media_type,
      library_reason?: not is_nil(item.library_container_id),
      watchlist_reason?: Discovery.on_watchlist?(item.tmdb_id, item.media_type),
      movie_in_library?: movie_in_library?(item)
    }

    if Reasons.retain?(facts) do
      :ok
    else
      delete_item(item)
      :ok
    end
  end

  # A single film in the library is complete — nothing left to release.
  # A `:movie` item linked to a MovieSeries tracks a TMDB *collection*,
  # whose id lives in a different namespace and so never matches here.
  defp movie_in_library?(%Item{media_type: :movie, tmdb_id: tmdb_id}) do
    ExternalIds.tmdb_owners([{tmdb_id, :movie}]) != %{}
  end

  defp movie_in_library?(%Item{}), do: false

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
  (`LibraryListener` calls this for every `entities_changed`): the
  database-side reconciliation runs inline — `LibraryLinks.refresh_for/1`
  and `complete_movie_tracking_for/1` — and the TMDB-side auto-tracking
  is enqueued as an `AutoTrackJob`, so an import never waits on the
  network.
  """
  @spec library_entities_changed([Ecto.UUID.t()]) :: :ok
  def library_entities_changed([]), do: :ok

  def library_entities_changed(entity_ids) when is_list(entity_ids) do
    LibraryLinks.refresh_for(entity_ids)
    complete_movie_tracking_for(entity_ids)
    {:ok, _job} = AutoTrackJob.enqueue(entity_ids)
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
  Every tracked title the machinery acts on — that is, every one whose
  mode is above `:none`. A disarmed title is inert by definition
  ([ADR-065]): it keeps no calendar and opens no wants, and exists only
  to carry the disarm.
  """
  @spec list_active_items() :: [Item.t()]
  def list_active_items do
    Repo.all(
      from(i in Item, where: i.tracking_mode != :none, order_by: [asc: i.name], preload: [:releases])
    )
  end

  def list_all_items do
    Repo.all(from(i in Item, order_by: [asc: i.name], preload: [:releases]))
  end

  def tracking_status({tmdb_id, media_type}) do
    case Repo.get_by(Item, tmdb_id: tmdb_id, media_type: media_type) do
      nil -> nil
      item -> item.tracking_mode
    end
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

  # --- Search & track-from-search (TMDB acquisition) ---
  #
  # Implementation lives in `ReleaseTracking.Acquisition`; these thin
  # delegators keep the context's public API stable for callers.

  @doc "See `MediaCentaur.ReleaseTracking.Acquisition.track_from_search/2`."
  @spec track_from_search(Title.t(), map()) :: {:ok, Item.t()} | {:error, term()}
  def track_from_search(%Title{} = title, opts \\ %{}), do: Acquisition.track_from_search(title, opts)

  @doc """
  Arms a title: puts it on the watchlist and starts tracking it
  ([ADR-065]).

  This is the one act a person performs. It is *a watchlist act* — the
  title lands on the list whichever surface the control was operated
  from — which is what keeps the invariant true: every active tracked
  title is either owned or on the watchlist.

  It lives here rather than in `Discovery` only because the dependency
  runs this way; `Discovery` must stay free of tracking. The seeded mode
  is `Reasons.seed_mode(:watchlist)` — `:watch`, never the global
  default, because auto-grab is opt-in and arming must not start a
  download. `opts[:tracking_mode]` names the mode a person chose on the
  control instead; a re-arm of a disarmed title takes the seed.

  Announces `Events.TrackingStarted` because this, unlike `track_item/1`,
  is a person's act.
  """
  @spec arm(Title.t(), map()) :: {:ok, Item.t()} | {:error, term()}
  def arm(%Title{} = title, opts \\ %{}) do
    with {:ok, _entry} <- Discovery.add_to_watchlist(title),
         {:ok, item} <- ensure_tracked(title, opts),
         {:ok, item} <- apply_armed_mode(item, opts) do
      announce_tracking_started(item)
      {:ok, item}
    end
  end

  # The mode the arm lands on. A person choosing one from the control
  # gets exactly that; otherwise a fresh arm keeps its seed, and a
  # re-arm of a disarmed title (the durable `:none`) takes the watchlist
  # seed — the person just chose to track it again, which is the one
  # raise that is theirs, not the system's.
  defp apply_armed_mode(%Item{tracking_mode: :none} = item, opts) do
    mode = Map.get(opts, :tracking_mode, Reasons.seed_mode(:watchlist))

    with {:ok, armed} <- set_tracking_mode(item, mode) do
      # A fresh track writes its own `:began_tracking` (`Acquisition`);
      # re-arming a disarmed title is the same beat for the activity feed.
      create_event!(%{
        item_id: armed.id,
        item_name: armed.name,
        event_type: :began_tracking,
        description: "Following releases of #{armed.name} again"
      })

      {:ok, armed}
    end
  end

  defp apply_armed_mode(%Item{} = item, %{tracking_mode: mode})
       when mode in [:watch, :ask, :grab, :global] and item.tracking_mode != mode,
       do: set_tracking_mode(item, mode)

  defp apply_armed_mode(%Item{} = item, _opts), do: {:ok, item}

  @doc """
  Disarms a title: sets its mode to `:none`, the durable record of a
  deliberate stop. The watchlist entry is untouched — de-listing is a
  separate act ([ADR-065]) — and the row survives even if every reason
  later drops, so re-acquiring the title cannot silently re-arm it.
  """
  @spec disarm(Item.t()) :: {:ok, Item.t()} | {:error, Ecto.Changeset.t()}
  def disarm(%Item{tracking_mode: :none} = item), do: {:ok, item}

  def disarm(%Item{} = item) do
    with {:ok, disarmed} <- set_tracking_mode(item, :none) do
      create_event!(%{
        item_id: disarmed.id,
        item_name: disarmed.name,
        event_type: :stopped_tracking,
        description: "New releases of #{disarmed.name} won't be picked up"
      })

      {:ok, disarmed}
    end
  end

  @doc """
  Fire-and-forget `arm/2`. Arming fetches the calendar from TMDB, so it
  runs on a supervised context-layer task — it must complete regardless of
  the triggering LiveView's lifecycle (ADR-049).
  """
  @spec arm_async(Title.t(), map()) :: :ok
  def arm_async(%Title{} = title, opts \\ %{}) do
    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn -> arm(title, opts) end)
    :ok
  end

  # Arming an already-tracked title must not re-fetch the calendar, and —
  # unless the person named a mode — must not overwrite one they set.
  defp ensure_tracked(%Title{} = title, opts) do
    case get_item_by_tmdb(title.tmdb_id, title.media_type) do
      nil -> Acquisition.track_from_search(title, opts)
      %Item{} = existing -> {:ok, existing}
    end
  end

  @doc "See `MediaCentaur.ReleaseTracking.Acquisition.track_from_search_async/2`."
  @spec track_from_search_async(Title.t(), map()) :: :ok
  def track_from_search_async(%Title{} = title, opts \\ %{}),
    do: Acquisition.track_from_search_async(title, opts)

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
            i.tracking_mode != :none and
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
            i.tracking_mode != :none and
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

  @doc "See `MediaCentaur.ReleaseTracking.Wants.open_gap_wants/2`."
  defdelegate open_gap_wants(item, unit_specs), to: Wants

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
            item.tracking_mode != :none and
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
