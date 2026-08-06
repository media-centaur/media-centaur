defmodule MediaCentaur.Library do
  use Boundary,
    deps: [MediaCentaur.Retention, MediaCentaur.Subtitles],
    exports: [
      AbsenceSweeper,
      Availability,
      Browser,
      Containers,
      ContentUrls,
      EntityShape,
      Episode,
      EpisodeList,
      Events,
      Events.EntitiesChanged,
      ExtraFile,
      ExternalId,
      ExternalIds,
      FileEventHandler,
      FilePresence,
      Image,
      ImageHealth,
      MediaTrackOverride,
      Movie,
      MovieList,
      MovieSeries,
      Person,
      PlayableItem,
      PlayableItems,
      Posters,
      Progress,
      Progress.Events,
      Progress.Events.ProgressFlushed,
      Progress.Events.ProgressHydrated,
      Progress.Events.ProgressTicked,
      Progress.Worker,
      ProgressRecords,
      ProgressSummary,
      Season,
      TVSeries,
      TypeResolver,
      VideoObject,
      Views,
      Views.BrowseItem,
      Views.ContinueWatching,
      Views.ContinueWatchingItem,
      Views.Detail,
      Views.DetailItem,
      Views.DetailItem.WatchedFile,
      Views.HeroCandidates,
      Views.HeroCandidatesItem,
      Views.RecentlyAdded,
      Views.RecentlyAddedItem,
      WatchedFile,
      Writes
    ]

  @moduledoc """
  The media library context — entities, images, external IDs, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  import Ecto.Query

  alias MediaCentaur.Repo

  alias MediaCentaur.Topics

  alias MediaCentaur.Library.{
    ChangeEntry,
    ContentUrls,
    ProgressRecords,
    Episode,
    Extra,
    ExtraFile,
    ExternalId,
    FileMediaInfo,
    FilePresence,
    HomeFeed,
    Image,
    MediaProbe,
    MediaTrackOverride,
    MoveMatcher,
    Movie,
    MovieSeries,
    PlayableItem,
    PresentableQueries,
    Season,
    TVSeries,
    VideoObject,
    WatchedFile,
    Writes
  }

  @doc "Subscribe the caller to library entity change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.library_updates())
  end

  # Leaf preload chain for materialising the virtual `content_url` field
  # (Library Schema v2 Phase 2 Task I). Owned by `Library.ContentUrls`,
  # which consumes it — see that moduledoc.
  @leaf_file_path_preload ContentUrls.required_preload()

  # ---------------------------------------------------------------------------
  # Search-index source
  # ---------------------------------------------------------------------------

  @doc """
  Returns the lightweight catalogue used by `Library.Views.Search` to
  rebuild its in-memory index.

  Unlike `Library.Browser.fetch_all_typed_entries/0`, this source is
  **presence-agnostic** — entities are included regardless of whether
  their backing files are currently reachable. Presence is computed
  per-entity by the Search projection (`Library.presentable_entity_ids/0`)
  so the `:present_only` filter does real work instead of being a
  tautology (Phase 3 Task C follow-up I-1).

  ## Hoist rule

  The same singleton-collection hoist Browser applies, but using the
  `_by_record_count` variants so categorisation is stable across file
  presence changes. A `MovieSeries` with one child Movie record is
  hoisted (the child surfaces in place of the collection); two or more
  child records surface as a collection container.

  ## Shape

  A list of maps with exactly the fields the Search projection consumes:

      %{
        id: container_id,
        type: :movie | :tv_series | :movie_series | :video_object,
        name: String.t() | nil,
        date_published: Date.t() | nil,
        # only populated for container types that walk into children:
        episode_ids: [Episode.id()] | nil,   # ordered (season_number, episode_number)
        movie_ids: [Movie.id()] | nil        # ordered (position, id)
      }

  Returns at most ~5 queries (one per kind), independent of library size.
  """
  @spec list_all_entities_for_search() :: [map()]
  def list_all_entities_for_search do
    list_search_standalone_movies() ++
      list_search_hoisted_movies() ++
      list_search_tv_series() ++
      list_search_movie_series() ++
      list_search_video_objects()
  end

  defp list_search_standalone_movies do
    from(m in PresentableQueries.standalone_movies_by_record_count(),
      select: %{id: m.id, name: m.name, date_published: m.date_published}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{type: :movie, episode_ids: nil, movie_ids: nil}))
  end

  defp list_search_hoisted_movies do
    from(m in PresentableQueries.singleton_collection_movies_by_record_count(),
      select: %{id: m.id, name: m.name, date_published: m.date_published}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{type: :movie, episode_ids: nil, movie_ids: nil}))
  end

  defp list_search_tv_series do
    # TVSeries: presence-agnostic source, with each series' episode IDs
    # walked in canonical play order. TVSeries has no `date_published`
    # column, so we resolve to nil. Two queries: the series, then a
    # bulk episode lookup keyed by `tv_series_id`.
    series_records =
      Repo.all(from(t in TVSeries, select: %{id: t.id, name: t.name}))

    series_ids = Enum.map(series_records, & &1.id)

    episodes_by_series =
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id in ^series_ids,
        order_by: [asc: s.tv_series_id, asc: s.season_number, asc: e.episode_number],
        select: {s.tv_series_id, e.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {tv_id, _ep_id} -> tv_id end, fn {_tv_id, ep_id} -> ep_id end)

    Enum.map(series_records, fn %{id: tv_id, name: name} ->
      %{
        id: tv_id,
        type: :tv_series,
        name: name,
        date_published: nil,
        episode_ids: Map.get(episodes_by_series, tv_id, []),
        movie_ids: nil
      }
    end)
  end

  defp list_search_movie_series do
    # MovieSeries: presence-agnostic source with the same `_by_record_count`
    # hoist rule Browser uses. Two queries: the series (with name +
    # date_published), then a bulk child-movie lookup keyed by
    # `movie_series_id`.
    series_records =
      Repo.all(
        from([ms] in PresentableQueries.multi_child_movie_series_by_record_count(),
          select: %{id: ms.id, name: ms.name, date_published: ms.date_published}
        )
      )

    series_ids = Enum.map(series_records, & &1.id)

    movies_by_series =
      from(m in Movie,
        where: m.movie_series_id in ^series_ids,
        order_by: [asc: m.movie_series_id, asc: m.position, asc: m.id],
        select: {m.movie_series_id, m.id}
      )
      |> Repo.all()
      |> Enum.group_by(fn {ms_id, _m_id} -> ms_id end, fn {_ms_id, m_id} -> m_id end)

    Enum.map(series_records, fn %{id: ms_id, name: name, date_published: date_published} ->
      %{
        id: ms_id,
        type: :movie_series,
        name: name,
        date_published: date_published,
        episode_ids: nil,
        movie_ids: Map.get(movies_by_series, ms_id, [])
      }
    end)
  end

  defp list_search_video_objects do
    from(v in VideoObject,
      select: %{id: v.id, name: v.name, date_published: v.date_published}
    )
    |> Repo.all()
    |> Enum.map(&Map.merge(&1, %{type: :video_object, episode_ids: nil, movie_ids: nil}))
  end

  @doc """
  Returns the set of `(container_type, container_id)` pairs that have at
  least one currently-present `WatchedFile`. Used by `Library.Views.Search`
  to mark `present?` per row at refresh time.

  Issues one bulk query through `library_playable_items →
  library_watched_files`; presence is structurally implied by the
  Phase-3 FK on `WatchedFile.file_presence_id` (cascade-delete from
  `Library.FilePresence`). For TVSeries / MovieSeries presence, the
  `container_type` is `:episode` / `:movie` — the Search projection
  rolls presence up to the container by membership in the precomputed
  `episode_ids` / `movie_ids` it already holds.

  Result shape: `MapSet.new([{:movie, uuid}, {:episode, uuid}, ...])`.
  """
  @spec presentable_entity_ids() :: MapSet.t({atom(), Ecto.UUID.t()})
  def presentable_entity_ids do
    query =
      from(pi in PlayableItem,
        join: wf in WatchedFile,
        on: wf.playable_item_id == pi.id,
        distinct: true,
        select: {pi.container_type, pi.container_id}
      )

    MapSet.new(Repo.all(query))
  end

  @doc """
  Bulk variant of "the canonical PlayableItem id per container". Takes a
  list of `{container_type, container_id}` pairs and returns
  `%{ {container_type, container_id} => playable_item_id }`. Containers
  with multiple PlayableItems resolve to the lowest-position one.

  Issues at most one query per distinct `container_type` in the input
  (so ≤ 3 queries total: `:movie`, `:episode`, `:video_object`).
  Containers absent from the result have no PlayableItem.
  """
  @spec representative_playable_item_ids_by_container([{atom(), Ecto.UUID.t()}]) ::
          %{{atom(), Ecto.UUID.t()} => Ecto.UUID.t()}
  def representative_playable_item_ids_by_container([]), do: %{}

  def representative_playable_item_ids_by_container(pairs) when is_list(pairs) do
    pairs
    |> Enum.group_by(fn {type, _id} -> type end, fn {_type, id} -> id end)
    |> Enum.flat_map(fn {type, ids} ->
      ids = Enum.uniq(ids)

      from(p in PlayableItem,
        where: p.container_type == ^type and p.container_id in ^ids,
        order_by: [asc: p.container_id, asc: p.position],
        select: {p.container_id, p.id}
      )
      |> Repo.all()
      # Group_by → keep first (lowest-position) per container.
      |> Enum.group_by(fn {container_id, _pi_id} -> container_id end)
      |> Enum.map(fn {container_id, [{_cid, pi_id} | _]} ->
        {{type, container_id}, pi_id}
      end)
    end)
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # WatchedFile
  # ---------------------------------------------------------------------------

  def list_watched_files, do: Repo.all(WatchedFile)

  def link_file(attrs) do
    file_path = Writes.attr(attrs, :file_path)
    media_dir = Writes.attr(attrs, :media_dir)
    attrs = ensure_file_presence_id(attrs, file_path, media_dir)

    result =
      case Repo.get_by(WatchedFile, file_path: file_path) do
        nil -> Repo.insert(WatchedFile.create_changeset(attrs))
        existing -> Repo.update(WatchedFile.update_changeset(existing, attrs))
      end

    case result do
      {:ok, %WatchedFile{} = watched_file} ->
        refresh_file_media_info(watched_file.file_presence_id, watched_file.file_path)

      _error ->
        :ok
    end

    result
  end

  def link_file!(attrs), do: Repo.bang!(link_file(attrs))

  def list_files_by_paths(file_paths) do
    Repo.all(from(w in WatchedFile, where: w.file_path in ^file_paths))
  end

  # ---------------------------------------------------------------------------
  # FileMediaInfo (ADR-057 derived data — see the schema moduledoc)
  # ---------------------------------------------------------------------------

  @doc """
  Probes `file_path` and upserts its `FileMediaInfo` row. `:skipped` when
  probing is unavailable/fails (missing ffprobe, unreadable file) or the
  file has no presence row — a later sweep can always retry, the data is
  recomputable.
  """
  @spec refresh_file_media_info(Ecto.UUID.t() | nil, String.t()) :: :ok | :skipped
  def refresh_file_media_info(nil, _file_path), do: :skipped

  def refresh_file_media_info(file_presence_id, file_path) do
    case MediaProbe.probe(file_path) do
      {:ok, attrs} ->
        attrs = Map.put(attrs, :file_presence_id, file_presence_id)

        case Repo.get_by(FileMediaInfo, file_presence_id: file_presence_id) do
          nil -> Repo.insert!(FileMediaInfo.changeset(%FileMediaInfo{}, attrs))
          existing -> Repo.update!(FileMediaInfo.changeset(existing, attrs))
        end

        :ok

      :error ->
        :skipped
    end
  end

  @doc "Media-info rows keyed by file path — batch read for view builders."
  @spec file_media_info_by_paths([String.t()]) :: %{String.t() => FileMediaInfo.t()}
  def file_media_info_by_paths([]), do: %{}

  def file_media_info_by_paths(paths) when is_list(paths) do
    from(f in FilePresence,
      join: m in FileMediaInfo,
      on: m.file_presence_id == f.id,
      where: f.file_path in ^paths,
      select: {f.file_path, m}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Backfill sweep: probes every file presence that has no media-info row
  yet (files imported before this feature, or whose probe failed).
  Idempotent and network-free; run from the boot heal
  (`Maintenance.probe_media_info_on_boot/1`).

  A sweep that filled anything broadcasts `entities_changed` once —
  the boot sweep finishes *after* the detail projection's boot build,
  so without the nudge the More-info pane would render from a cache
  snapshotted while the table was still empty.
  """
  @spec probe_missing_media_info() :: %{probed: non_neg_integer(), skipped: non_neg_integer()}
  def probe_missing_media_info do
    {summary, probed_presence_ids} =
      from(f in FilePresence,
        left_join: m in FileMediaInfo,
        on: m.file_presence_id == f.id,
        where: is_nil(m.id),
        select: {f.id, f.file_path}
      )
      |> Repo.all()
      |> Enum.reduce({%{probed: 0, skipped: 0}, []}, fn {presence_id, path}, {acc, ids} ->
        case refresh_file_media_info(presence_id, path) do
          :ok -> {%{acc | probed: acc.probed + 1}, [presence_id | ids]}
          :skipped -> {%{acc | skipped: acc.skipped + 1}, ids}
        end
      end)

    if summary.probed > 0 do
      probed_presence_ids
      |> top_level_entity_ids_for_presences()
      |> broadcast_entities_changed()
    end

    summary
  end

  # Top-level entity ids (Movie / TVSeries / VideoObject) for the watched
  # files behind the given presence rows — batched, two queries.
  defp top_level_entity_ids_for_presences(presence_ids) do
    containers =
      Repo.all(
        from(w in WatchedFile,
          join: p in PlayableItem,
          on: p.id == w.playable_item_id,
          where: w.file_presence_id in ^presence_ids,
          select: {p.container_type, p.container_id}
        )
      )

    {episode_ids, direct_ids} =
      Enum.reduce(containers, {[], []}, fn
        {:episode, id}, {episodes, direct} -> {[id | episodes], direct}
        {_type, id}, {episodes, direct} -> {episodes, [id | direct]}
      end)

    series_ids =
      if episode_ids == [] do
        []
      else
        Repo.all(
          from(e in Episode,
            join: s in Season,
            on: s.id == e.season_id,
            where: e.id in ^episode_ids,
            select: s.tv_series_id
          )
        )
      end

    Enum.uniq(direct_ids ++ series_ids)
  end

  @doc """
  Resolves a WatchedFile to its top-level entity id — the Movie /
  TVSeries / VideoObject the user navigated to in the library. Used by
  the cleanup cascade in `Library.FileEventHandler` (replaces the
  pre-Phase-2 `WatchedFile.owner_id/1` coalescer).

  Walks `WatchedFile → PlayableItem → container`:

    * `:movie` / `:video_object` — container_id is already the
      top-level entity.
    * `:episode` — climbs `Episode → Season → TVSeries.id`.

  Returns `nil` if the WatchedFile is dangling (no PlayableItem) or the
  container has been deleted out from under it.
  """
  @spec top_level_entity_id_for_watched_file(WatchedFile.t()) :: Ecto.UUID.t() | nil
  def top_level_entity_id_for_watched_file(%WatchedFile{playable_item_id: nil}), do: nil

  def top_level_entity_id_for_watched_file(%WatchedFile{playable_item_id: pi_id}) do
    case Repo.get(PlayableItem, pi_id) do
      nil ->
        nil

      %PlayableItem{container_type: type, container_id: container_id}
      when type in [:movie, :video_object] ->
        container_id

      %PlayableItem{container_type: :episode, container_id: episode_id} ->
        Repo.one(
          from(e in Episode,
            join: s in Season,
            on: s.id == e.season_id,
            where: e.id == ^episode_id,
            select: s.tv_series_id
          )
        )
    end
  end

  def list_files_by_media_dir(media_dir) do
    Repo.all(from(w in WatchedFile, where: w.media_dir == ^media_dir))
  end

  @doc """
  Paths of already-imported files that live under `dir` — used to check
  whether a folder is safe to delete wholesale (it isn't, if anything
  other than the files being deleted also lives there). Filters in
  Elixir rather than a SQL `LIKE` so a literal `%`/`_` in a real path
  can't be misread as a wildcard.
  """
  @spec watched_file_paths_under(String.t()) :: [String.t()]
  def watched_file_paths_under(dir) do
    prefix = dir <> "/"

    from(w in WatchedFile, select: w.file_path)
    |> Repo.all()
    |> Enum.filter(&String.starts_with?(&1, prefix))
  end

  @doc """
  Relink-on-move. Given newly-seen `{path, size}` pairs under
  `new_media_dir`, re-point any that `MoveMatcher` recognises as a file
  that *moved* — rewriting the `WatchedFile` / `ExtraFile` rows and the
  `FilePresence` ledger to the new location — instead of letting them
  import as brand-new entities.

  A match is acted on only when the old path is actually gone on disk
  (`:exists?`, default `&File.regular?/1`), which distinguishes a move
  from a copy. Returns `%{relinked: [path], still_new: [path]}`; the
  caller dispatches only `still_new` to the import pipeline.
  """
  @spec relink_moved_files([{String.t(), non_neg_integer() | nil}], String.t(), keyword()) ::
          %{relinked: [String.t()], still_new: [String.t()]}
  def relink_moved_files(new_files, new_media_dir, opts \\ [])

  def relink_moved_files([], _new_media_dir, _opts), do: %{relinked: [], still_new: []}

  def relink_moved_files(new_files, new_media_dir, opts) do
    exists? = Keyword.get(opts, :exists?, &File.regular?/1)

    sizes = new_files |> Enum.map(&elem(&1, 1)) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    candidates = FilePresence.list_relink_candidates(sizes)

    {moves, still_new} =
      Enum.reduce(new_files, {[], []}, fn {path, size}, {moves, still_new} ->
        case MoveMatcher.match(%{path: path, media_dir: new_media_dir, size: size}, candidates) do
          {:move, old} ->
            # Old path still on disk → a copy, not a move. Let it import.
            if exists?.(old.file_path),
              do: {moves, [path | still_new]},
              else: {[{old, path, size} | moves], still_new}

          :no_match ->
            {moves, [path | still_new]}
        end
      end)

    %{
      relinked: moves |> Enum.reverse() |> perform_relinks(new_media_dir),
      still_new: Enum.reverse(still_new)
    }
  end

  defp perform_relinks([], _new_media_dir), do: []

  defp perform_relinks(moves, new_media_dir) do
    now = DateTime.utc_now()
    now_seconds = DateTime.truncate(now, :second)

    {:ok, {relinked, entity_ids}} =
      Repo.transaction(fn ->
        Enum.reduce(moves, {[], []}, fn {old, new_path, new_size}, {paths, ids} ->
          moved_entity_ids =
            [old.file_path]
            |> list_files_by_paths()
            |> Enum.map(&top_level_entity_id_for_watched_file/1)
            |> Enum.reject(&is_nil/1)

          Repo.update_all(from(w in WatchedFile, where: w.file_path == ^old.file_path),
            set: [file_path: new_path, media_dir: new_media_dir]
          )

          Repo.update_all(from(ef in ExtraFile, where: ef.file_path == ^old.file_path),
            set: [file_path: new_path, media_dir: new_media_dir]
          )

          Repo.update_all(from(p in FilePresence, where: p.id == ^old.id),
            set: [
              file_path: new_path,
              media_dir: new_media_dir,
              size: new_size,
              last_seen_at: now,
              updated_at: now_seconds
            ]
          )

          {[new_path | paths], ids ++ moved_entity_ids}
        end)
      end)

    broadcast_entities_changed(Enum.uniq(entity_ids))
    Enum.reverse(relinked)
  end

  @doc """
  Returns the on-disk file path for a PlayableItem's currently-present
  file, or `nil` when no `WatchedFile` for the item exists.

  Reads `WatchedFile.file_path` directly — presence is structurally
  guaranteed by the Phase-3 FK on `WatchedFile.file_presence_id`
  (cascade-delete from `Library.FilePresence`). Replaces the
  `Movie.content_url` / `Episode.content_url` / `VideoObject.content_url`
  reads removed in Library Schema v2 Phase 2 Task I — after that task
  `WatchedFile.file_path` is the sole source of truth for "the file on
  disk for this playable thing."

  When a PlayableItem has multiple WatchedFiles (rare; only the
  director's-cut / multi-cut shape produces this), the first match by
  insertion order wins. Callers that need every variant should query
  `WatchedFile` directly.
  """
  @spec playable_file_path(Ecto.UUID.t()) :: String.t() | nil
  def playable_file_path(playable_item_id) when is_binary(playable_item_id) do
    Repo.one(
      from(w in WatchedFile,
        where: w.playable_item_id == ^playable_item_id,
        order_by: [asc: w.inserted_at],
        limit: 1,
        select: w.file_path
      )
    )
  end

  def playable_file_path(_), do: nil

  @doc """
  Returns an Ecto subquery selecting `file_path` from every linked
  WatchedFile. Exposed so cross-context queries (Watcher's
  `rescan_unlinked`) can compose against linked-file state without
  reaching into the WatchedFile schema directly.
  """
  def linked_file_paths_subquery do
    from(w in WatchedFile, select: w.file_path)
  end

  @doc """
  Lists watched files that belong to the given top-level entity, regardless of
  which container type owns them. Used when you have an entity UUID but don't
  know which type table it lives in (e.g. `Inbound.handle_rematch/1`).

  Resolution walks through PlayableItem (Library Schema v2 Phase 2 Task B):

    * Movie / VideoObject — direct lookup by container_id.
    * Episode — through the season's TVSeries id.
    * MovieSeries — through child Movies' container ids.
  """
  def list_watched_files_by_entity_id(entity_id) do
    movie_or_video_subquery =
      from(p in PlayableItem,
        where: p.container_type in [:movie, :video_object] and p.container_id == ^entity_id,
        select: p.id
      )

    episode_subquery =
      from(p in PlayableItem,
        join: e in Episode,
        on: e.id == p.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: p.container_type == :episode and s.tv_series_id == ^entity_id,
        select: p.id
      )

    movie_series_child_subquery =
      from(p in PlayableItem,
        join: m in Movie,
        on: m.id == p.container_id,
        where: p.container_type == :movie and m.movie_series_id == ^entity_id,
        select: p.id
      )

    Repo.all(
      from(w in WatchedFile,
        where:
          w.playable_item_id in subquery(movie_or_video_subquery) or
            w.playable_item_id in subquery(episode_subquery) or
            w.playable_item_id in subquery(movie_series_child_subquery)
      )
    )
  end

  @doc """
  Lists seasons for a TV series by its ID.
  """
  def list_seasons_by_owner_id(owner_id) do
    Repo.all(from(s in Season, where: s.tv_series_id == ^owner_id))
  end

  @doc """
  Lists movies for a movie series or standalone by their FK.
  """
  def list_movies_by_owner_id(owner_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    # Preload the WatchedFile chain so the virtual `content_url`
    # populates on the returned Movie structs (Library Schema v2
    # Phase 2 Task I).
    full_preloads = List.flatten([@leaf_file_path_preload | preloads])

    from(m in Movie, where: m.movie_series_id == ^owner_id)
    |> Repo.all()
    |> Repo.preload(full_preloads)
    |> Enum.map(&ContentUrls.populate/1)
  end

  @doc """
  Lists extras owned by the given UUID — works for any owner type
  (movie / tv_series / movie_series / season) because the
  `(owner_type, owner_id)` discriminator makes the type irrelevant to
  the lookup. Callers that need only one owner type should query
  `Extra` directly.
  """
  def list_extras_by_owner_id(owner_id) do
    Repo.all(from(x in Extra, where: x.owner_id == ^owner_id))
  end

  @doc """
  Resolves any entity id + current possession to a **presentable
  identity** — a `{kind, id}` pair — applying the single movie-vs-collection
  hoist rule. This is the one authority every read surface consults
  (browse grid, detail modal, now-playing), so the surfaces can never
  disagree about whether something is a movie or a collection.

  Rules:

    * standalone movie (present) → `{:movie, id}`
    * collection with exactly one present movie → `{:movie, sole_child_id}`
      (the collection is hoisted away; the child carries a collection
      reference for the badge)
    * collection with two or more present movies → `{:movie_series, id}`
    * a movie inside a 2+-present collection → `{:movie_series, ms_id}`
      (it isn't a top-level entity; its collection is — matches the grid)
    * tv series with a present episode → `{:tv_series, id}`
    * present video object → `{:video_object, id}`
    * anything absent / unknown → `:not_found`
  """
  @spec resolve_presentable(Ecto.UUID.t()) ::
          {:tv_series | :movie_series | :movie | :video_object, Ecto.UUID.t()} | :not_found
  def resolve_presentable(id) when is_binary(id) do
    cond do
      tv_series_present?(id) -> {:tv_series, id}
      Repo.exists?(from(ms in MovieSeries, where: ms.id == ^id)) -> resolve_collection(id)
      movie = Repo.get(Movie, id) -> resolve_movie(movie)
      video_object_present?(id) -> {:video_object, id}
      true -> :not_found
    end
  end

  defp resolve_collection(movie_series_id) do
    case Repo.all(PresentableQueries.present_movie_ids(movie_series_id)) do
      [] -> :not_found
      [sole_child_id] -> {:movie, sole_child_id}
      _multiple -> {:movie_series, movie_series_id}
    end
  end

  defp resolve_movie(%Movie{id: id, movie_series_id: nil}) do
    if movie_present?(id), do: {:movie, id}, else: :not_found
  end

  defp resolve_movie(%Movie{id: id, movie_series_id: movie_series_id}) do
    case Repo.all(PresentableQueries.present_movie_ids(movie_series_id)) do
      [_, _ | _] = _multiple -> {:movie_series, movie_series_id}
      _zero_or_one -> if movie_present?(id), do: {:movie, id}, else: :not_found
    end
  end

  defp tv_series_present?(tv_series_id) do
    Repo.exists?(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on: pi.id == wf.playable_item_id and pi.container_type == :episode,
        join: e in Episode,
        on: e.id == pi.container_id,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id == ^tv_series_id
      )
    )
  end

  defp movie_present?(movie_id), do: container_present?(:movie, movie_id)
  defp video_object_present?(video_object_id), do: container_present?(:video_object, video_object_id)

  defp container_present?(container_type, container_id) do
    Repo.exists?(
      from(wf in WatchedFile,
        join: pi in PlayableItem,
        on: pi.id == wf.playable_item_id and pi.container_type == ^container_type,
        where: pi.container_id == ^container_id
      )
    )
  end

  @doc """
  Loads a single library entry shaped for the detail modal — the
  `%{entity, progress, progress_records}` triple every host LiveView
  assigns to `:selected_entry`.

  Reads from `MediaCentaur.Library.Views.Detail` (Pillar-2 ETS
  projection, microsecond reads in production; live DB-fallback in test
  mode) — probes each container kind in turn and converts the first
  match's `DetailItem` to the legacy entity-map shape via
  `Views.DetailItem.to_entity_map/1`. Progress records come from
  `list_progress_records_for_container/2`; the summary from
  `ProgressSummary.compute/2`.

  Returns `:not_found` when no container matches *and has at least one
  present file* — orphan entities (record exists, no `WatchedFile`)
  don't appear in the modal. Same gating
  `Browser.fetch_typed_entries_by_ids/1` applied pre-Phase-3.2; the
  presence check now walks the projection's `present?` flags (or
  `:seasons/:movies` trees for series containers).

  Library Schema v2 Phase 3.2 Task D flipped this from the
  `Browser + load_extras_for_entity` chain to the projection.
  `load_extras_for_entity/1` is retired — extras flow on the DetailItem
  now.
  """
  @spec load_modal_entry(Ecto.UUID.t()) ::
          {:ok, %{entity: map(), progress: map() | nil, progress_records: list()}}
          | :not_found
  def load_modal_entry(id) when is_binary(id) do
    # Route through the single presentable authority: it applies the hoist
    # rule once (so opening a hoisted collection by its series id correctly
    # lands on the sole movie), then we build the view for the resolved
    # kind. `to_entity_map/1` keys off the projection's `presented_as`, so
    # the resolved kind and the built entity always agree.
    with {kind, resolved_id} <- resolve_presentable(id),
         item when not is_nil(item) <- present_detail_for(kind, resolved_id) do
      {:ok, build_modal_entry(kind, item, resolved_id)}
    else
      _ -> :not_found
    end
  end

  defp present_detail_for(container_type, id) do
    case __MODULE__.Views.detail_by_container(container_type, id) do
      nil ->
        nil

      %__MODULE__.Views.DetailItem{} = item ->
        if any_present?(container_type, item), do: item
    end
  end

  defp any_present?(:tv_series, %__MODULE__.Views.DetailItem{seasons: seasons}) do
    Enum.any?(seasons || [], fn season ->
      Enum.any?(season.episodes || [], & &1.present?)
    end)
  end

  defp any_present?(:movie_series, %__MODULE__.Views.DetailItem{movies: movies}) do
    Enum.any?(movies || [], & &1.present?)
  end

  defp any_present?(_type, %__MODULE__.Views.DetailItem{present?: present}), do: present == true

  defp build_modal_entry(container_type, item, id) do
    entity = item |> __MODULE__.Views.DetailItem.to_entity_map() |> put_track_override()
    progress_records = ProgressRecords.list_for_container(container_type, id)
    progress = MediaCentaur.Library.ProgressSummary.compute(entity, progress_records)

    %{entity: entity, progress: progress, progress_records: progress_records}
  end

  # ---------------------------------------------------------------------------
  # Image
  # ---------------------------------------------------------------------------

  def list_all_images, do: Repo.all(Image)

  def create_image(attrs) do
    Repo.insert(Image.create_changeset(translate_image_owner(attrs)))
  end

  def create_image!(attrs), do: Repo.bang!(create_image(attrs))

  def upsert_image(attrs, conflict_target) do
    attrs = translate_image_owner(attrs)
    delete_replaced_image_file(attrs, conflict_target)

    Repo.insert(Image.create_changeset(attrs),
      on_conflict: {:replace, [:content_url, :extension, :updated_at]},
      conflict_target: conflict_target
    )
  end

  # Image paths are deterministic (`{owner_id}/{role}.{extension}`), so a
  # re-download normally overwrites in place — but when the extension
  # changes (poster.jpg → poster.png) the upsert re-points `content_url`
  # and the old file would linger on disk forever. Remove it before the
  # row is replaced, while we can still see the old path.
  defp delete_replaced_image_file(attrs, conflict_target) when is_list(conflict_target) do
    lookup = Enum.map(conflict_target, fn key -> {key, Map.get(attrs, key)} end)

    with false <- Enum.any?(lookup, fn {_key, value} -> is_nil(value) end),
         %Image{content_url: old_url} when is_binary(old_url) <- Repo.get_by(Image, lookup),
         new_url when new_url != old_url <- Map.get(attrs, :content_url),
         old_path when is_binary(old_path) <- MediaCentaur.Config.resolve_image_path(old_url) do
      File.rm(old_path)
    else
      _no_replaced_file -> :ok
    end
  end

  # Legacy per-type FK shape kept for callers and tests written before
  # Phase 2 Task D — translate at the context boundary so the call sites
  # don't need to change all at once. New code should pass `owner_type`
  # + `owner_id` directly.
  @image_owner_legacy_keys [
    movie_id: :movie,
    episode_id: :episode,
    tv_series_id: :tv_series,
    movie_series_id: :movie_series,
    video_object_id: :video_object
  ]
  defp translate_image_owner(attrs) when is_map(attrs),
    do: translate_legacy_owner(attrs, @image_owner_legacy_keys)

  @extra_owner_legacy_keys [
    movie_id: :movie,
    tv_series_id: :tv_series,
    movie_series_id: :movie_series,
    season_id: :season
  ]
  defp translate_extra_owner(attrs) when is_map(attrs),
    do: translate_legacy_owner(attrs, @extra_owner_legacy_keys)

  @external_id_owner_legacy_keys [
    movie_id: :movie,
    tv_series_id: :tv_series,
    movie_series_id: :movie_series,
    video_object_id: :video_object
  ]
  defp translate_external_id_owner(attrs) when is_map(attrs),
    do: translate_legacy_owner(attrs, @external_id_owner_legacy_keys)

  defp translate_legacy_owner(attrs, legacy_keys) do
    case Enum.find(legacy_keys, fn {key, _} -> not is_nil(Map.get(attrs, key)) end) do
      nil ->
        attrs

      {legacy_key, owner_type} ->
        attrs
        |> Map.drop(Keyword.keys(legacy_keys))
        |> Map.put_new(:owner_type, owner_type)
        |> Map.put_new(:owner_id, Map.get(attrs, legacy_key))
    end
  end

  @doc """
  Lists the `Library.Image` rows owned by `(owner_type, owner_id)`.

  The discriminator pair is the canonical image ownership key
  (Library Schema v2 Phase 1) — `owner_type` is one of `:movie`,
  `:episode`, `:tv_series`, `:movie_series`, `:video_object`. Used by the
  inbound link-time artwork backfill to learn which roles a container is
  already missing.
  """
  @spec list_images(atom(), Ecto.UUID.t()) :: [Image.t()]
  def list_images(owner_type, owner_id) when is_atom(owner_type) and is_binary(owner_id) do
    Repo.all(from i in Image, where: i.owner_type == ^owner_type and i.owner_id == ^owner_id)
  end

  @doc """
  Resolves logo URLs for a list of `{media_type, entity_id}` pairs in a single
  query. Returns a `%{entity_id => "/media-images/<content_url>"}` map for any
  pair whose corresponding entity has a logo image. Entries without a logo are
  simply absent from the result.

  Used by views that render tracked-show cards (Upcoming, Coming Up) so they
  can fall back from typography to the show logo without per-card lookups.
  """
  @spec logo_urls_for_entities([{:movie | :tv_series, Ecto.UUID.t()}]) :: %{
          Ecto.UUID.t() => String.t()
        }
  def logo_urls_for_entities([]), do: %{}

  def logo_urls_for_entities(pairs) when is_list(pairs) do
    movie_ids = for {:movie, id} <- pairs, is_binary(id), do: id
    tv_ids = for {:tv_series, id} <- pairs, is_binary(id), do: id

    rows =
      Repo.all(
        from i in Image,
          where:
            i.role == "logo" and
              ((i.owner_type == :movie and i.owner_id in ^movie_ids) or
                 (i.owner_type == :tv_series and i.owner_id in ^tv_ids)),
          select: {i.owner_id, i.content_url}
      )

    Map.new(rows, fn {entity_id, content_url} ->
      {entity_id, Image.web_path(content_url)}
    end)
  end

  # ---------------------------------------------------------------------------
  # ExternalId
  # ---------------------------------------------------------------------------

  def create_external_id(attrs) do
    Repo.insert(ExternalId.create_changeset(translate_external_id_owner(attrs)))
  end

  def create_external_id!(attrs), do: Repo.bang!(create_external_id(attrs))

  @doc """
  Returns the container of the given type that owns the given TMDB id
  (via `library_external_ids`), or `nil`.

  Library Schema v2 Phase 2 Task F collapsed the per-type FKs on
  `ExternalId` into a single `(owner_type, owner_id)` discriminator
  pair. This helper joins on the discriminator to fetch the typed
  container in a single query.

  Pass `:tmdb_collection` for MovieSeries; everything else uses
  `:tmdb`.
  """
  @spec find_by_external_id(MediaCentaur.Library.ExternalIds.owner_type(), String.t()) ::
          MediaCentaur.Library.ExternalIds.owner() | nil
  def find_by_external_id(owner_type, external_id) when is_atom(owner_type) and is_binary(external_id) do
    source = if owner_type == :movie_series, do: "tmdb_collection", else: "tmdb"
    schema = schema_for_owner_type(owner_type)

    Repo.one(
      from(r in schema,
        join: e in ExternalId,
        on: e.owner_id == r.id and e.owner_type == ^owner_type,
        where: e.source == ^source and e.external_id == ^external_id,
        limit: 1
      )
    )
  end

  defp schema_for_owner_type(:movie), do: Movie
  defp schema_for_owner_type(:tv_series), do: TVSeries
  defp schema_for_owner_type(:movie_series), do: MovieSeries
  defp schema_for_owner_type(:video_object), do: VideoObject

  @doc """
  Returns `{:ok, file_path}` if the library has a movie with this TMDB
  id whose file has been linked (a `WatchedFile` exists for the movie's
  `PlayableItem`), otherwise `:not_found`. Used by
  `Acquisition.Pursuits.LibraryReconciler` as the safety-net check
  against the PubSub-driven completion path.

  After Library Schema v2 Phase 2 Task I the on-disk path lives on
  `library_watched_files.file_path` via `PlayableItem`; this query
  walks `Movie → PlayableItem → WatchedFile` rather than reading a
  former `content_url` column on Movie.
  """
  @spec find_present_movie(String.t()) :: {:ok, String.t()} | :not_found
  def find_present_movie(tmdb_id) when is_binary(tmdb_id) do
    case Repo.one(
           from(m in Movie,
             join: e in ExternalId,
             on: e.owner_id == m.id and e.owner_type == :movie,
             join: pi in PlayableItem,
             on: pi.container_id == m.id and pi.container_type == :movie,
             join: w in WatchedFile,
             on: w.playable_item_id == pi.id,
             where: e.source == "tmdb" and e.external_id == ^tmdb_id,
             select: w.file_path,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns `{:ok, file_path}` if the library has an episode for the
  given `(tmdb_id, season_number, episode_number)` tuple whose file has
  been linked, otherwise `:not_found`. Joins through
  `TVSeries → Season → Episode → PlayableItem → WatchedFile` in a
  single query.
  """
  @spec find_present_episode(String.t(), integer(), integer()) ::
          {:ok, String.t()} | :not_found
  def find_present_episode(tmdb_id, season_number, episode_number)
      when is_binary(tmdb_id) and is_integer(season_number) and is_integer(episode_number) do
    case Repo.one(
           from(e in Episode,
             join: s in Season,
             on: s.id == e.season_id,
             join: t in TVSeries,
             on: t.id == s.tv_series_id,
             join: ext in ExternalId,
             on: ext.owner_id == t.id and ext.owner_type == :tv_series,
             join: pi in PlayableItem,
             on: pi.container_id == e.id and pi.container_type == :episode,
             join: w in WatchedFile,
             on: w.playable_item_id == pi.id,
             where:
               ext.source == "tmdb" and ext.external_id == ^tmdb_id and
                 s.season_number == ^season_number and
                 e.episode_number == ^episode_number,
             select: w.file_path,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns the set of `{season_number, episode_number}` pairs for a TV
  series whose episode has a linked file on disk — the "present-set" used
  by reconciliation to mark which canonical spine nodes are already filled.
  """
  @spec present_episode_keys(Ecto.UUID.t()) :: MapSet.t({integer(), integer()})
  def present_episode_keys(tv_series_id) when is_binary(tv_series_id) do
    from(e in Episode,
      join: s in Season,
      on: s.id == e.season_id,
      join: pi in PlayableItem,
      on: pi.container_id == e.id and pi.container_type == :episode,
      join: w in WatchedFile,
      on: w.playable_item_id == pi.id,
      where: s.tv_series_id == ^tv_series_id,
      distinct: true,
      select: {s.season_number, e.episode_number}
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Returns every on-disk file path currently linked to a `PlayableItem`
  (i.e. present in the library).

  Used by `Acquisition.Pursuits.LibraryReconciler` to satisfy
  prowlarr-query pursuits, which carry no TMDB id to match on — the only
  binding back to the library is the downloaded file's name, so the
  reconciler matches the pursuit's release title against these basenames.
  """
  @spec list_present_file_paths() :: [String.t()]
  def list_present_file_paths do
    Repo.all(from(w in WatchedFile, select: w.file_path))
  end

  @doc """
  Returns `{tv_series_id, tmdb_id}` pairs for TV series in the given list
  that have a TMDB ExternalId row.
  """
  def tmdb_ids_for_tv_series(tv_series_ids) when is_list(tv_series_ids) do
    Repo.all(
      from(t in TVSeries,
        join: e in ExternalId,
        on: e.owner_id == t.id and e.owner_type == :tv_series,
        where: t.id in ^tv_series_ids and e.source == "tmdb",
        select: {t.id, e.external_id}
      )
    )
  end

  @doc """
  Returns `{movie_id, tmdb_id}` pairs for movies in the given list that
  have a TMDB ExternalId row. Mirror of `tmdb_ids_for_tv_series/1` —
  release tracking uses this to detect when a tracked movie has just
  landed in the library so it can close out the tracking item.
  """
  def tmdb_ids_for_movies(movie_ids) when is_list(movie_ids) do
    Repo.all(
      from(m in Movie,
        join: e in ExternalId,
        on: e.owner_id == m.id and e.owner_type == :movie,
        where: m.id in ^movie_ids and e.source == "tmdb",
        select: {m.id, e.external_id}
      )
    )
  end

  @doc """
  Returns every entity in the library that has a TMDB ExternalId,
  tagged with its type. Used by ReleaseTracking to scan for tracking
  candidates.

  Each row is `%{source: String.t(), external_id: String.t(),
  owner_type: atom(), owner_id: Ecto.UUID.t()}`. The `:source` is
  `"tmdb"` for movies / TV / video objects and `"tmdb_collection"` for
  movie series; `:owner_type` is the canonical container type atom.

  Standalone movies (no `movie_series_id`) are surfaced; movies that
  belong to a movie_series are skipped — release tracking handles them
  through the collection.
  """
  def list_tmdb_entities do
    tv_and_movie_series =
      Repo.all(
        from(e in ExternalId,
          where:
            (e.owner_type == :tv_series and e.source == "tmdb") or
              (e.owner_type == :movie_series and e.source == "tmdb_collection"),
          select: %{
            source: e.source,
            external_id: e.external_id,
            owner_type: e.owner_type,
            owner_id: e.owner_id
          }
        )
      )

    standalone_movies =
      Repo.all(
        from(m in Movie,
          join: e in ExternalId,
          on: e.owner_id == m.id and e.owner_type == :movie,
          where: e.source == "tmdb" and is_nil(m.movie_series_id),
          select: %{
            source: e.source,
            external_id: e.external_id,
            owner_type: e.owner_type,
            owner_id: e.owner_id
          }
        )
      )

    tv_and_movie_series ++ standalone_movies
  end

  # ---------------------------------------------------------------------------
  # Extra
  # ---------------------------------------------------------------------------

  def list_extras_for_season(season_id) do
    Repo.all(from(x in Extra, where: x.owner_type == :season and x.owner_id == ^season_id))
  end

  def fetch_extra(id) do
    case Repo.get(Extra, id) do
      nil -> {:error, :not_found}
      extra -> {:ok, extra}
    end
  end

  @doc """
  Find or create an extra by its `(owner_type, owner_id, content_url)`
  tuple. Used by ingest to upsert extras without re-discovering the
  same bonus feature on every Watcher event.
  """
  def find_or_create_extra_by_owner(attrs) do
    Writes.find_or_insert_by(
      Extra,
      [
        owner_type: Writes.attr(attrs, :owner_type),
        owner_id: Writes.attr(attrs, :owner_id),
        content_url: Writes.attr(attrs, :content_url)
      ],
      attrs
    )
  end

  def create_extra(attrs) do
    Repo.insert(Extra.create_changeset(translate_extra_owner(attrs)))
  end

  def create_extra!(attrs), do: Repo.bang!(create_extra(attrs))

  @doc """
  Re-derives an extra's display name. The only update path for `Extra.name`;
  rejects a blank value via `Extra.update_name_changeset/2`. Used by the
  re-derive sweep (`MediaCentaur.Pipeline.ExtraRederive`).
  """
  @spec update_extra_name(Extra.t(), String.t() | nil) ::
          {:ok, Extra.t()} | {:error, Ecto.Changeset.t()}
  def update_extra_name(%Extra{} = extra, name) do
    extra
    |> Extra.update_name_changeset(%{name: name})
    |> Repo.update()
  end

  @doc """
  Extras whose `name` can be re-derived from a file path — i.e. those carrying a
  `content_url`. Drives the re-derive sweep (`Pipeline.ExtraRederive`).
  """
  @spec list_rederivable_extras() :: [Extra.t()]
  def list_rederivable_extras do
    Repo.all(from(e in Extra, where: not is_nil(e.content_url)))
  end

  @doc """
  Count of extras with a blank or missing `name` — the visible symptom the
  re-derive sweep repairs; drives the Maintenance button's prominence.
  """
  @spec count_blank_extra_names() :: non_neg_integer()
  def count_blank_extra_names do
    Repo.aggregate(from(e in Extra, where: is_nil(e.name) or e.name == ""), :count)
  end

  # ---------------------------------------------------------------------------
  # ExtraFile (file presence for Extras — parallel to WatchedFile for
  # PlayableItems)
  # ---------------------------------------------------------------------------

  @doc """
  Inserts (or re-points by `file_path`) an `ExtraFile` row linking a
  bonus-feature path on disk to an `Library.Extra`. Mirrors `link_file/1`
  for `WatchedFile`.
  """
  @spec create_extra_file(map()) :: {:ok, ExtraFile.t()} | {:error, Ecto.Changeset.t()}
  def create_extra_file(attrs) do
    file_path = Writes.attr(attrs, :file_path)
    media_dir = Writes.attr(attrs, :media_dir)
    attrs = ensure_file_presence_id(attrs, file_path, media_dir)

    case Repo.get_by(ExtraFile, file_path: file_path) do
      nil -> Repo.insert(ExtraFile.create_changeset(attrs))
      existing -> Repo.update(ExtraFile.update_changeset(existing, attrs))
    end
  end

  @doc "Bang variant of `create_extra_file/1` — raises on changeset error."
  @spec create_extra_file!(map()) :: ExtraFile.t()
  def create_extra_file!(attrs), do: Repo.bang!(create_extra_file(attrs))

  @doc "Lists all ExtraFile rows for an extra_id."
  @spec list_extra_files_for(Ecto.UUID.t()) :: [ExtraFile.t()]
  def list_extra_files_for(extra_id) when is_binary(extra_id) do
    Repo.all(from(f in ExtraFile, where: f.extra_id == ^extra_id))
  end

  @doc "Deletes an ExtraFile row."
  @spec destroy_extra_file(ExtraFile.t()) :: {:ok, ExtraFile.t()} | {:error, Ecto.Changeset.t()}
  def destroy_extra_file(extra_file), do: Repo.delete(extra_file)

  @doc """
  Backfills `ExtraFile` rows for extras imported before the ingest path wrote
  them — those carrying a `content_url`, lacking any `ExtraFile`, and with a
  resolvable `FilePresence` for the path (the source of `media_dir`). Network-free
  and idempotent; runs on boot so existing extras become "linked" and stop being
  re-emitted by `rescan_unlinked`. Returns `%{created: n}`.
  """
  @spec backfill_extra_files() :: %{created: non_neg_integer()}
  def backfill_extra_files do
    query =
      from(e in Extra,
        left_join: f in ExtraFile,
        on: f.extra_id == e.id,
        where: not is_nil(e.content_url) and is_nil(f.id),
        select: e
      )

    extras = Repo.all(query)

    # Resolve every media_dir in one query instead of one Repo.get_by per
    # extra (this runs on boot over the whole unlinked-extra set).
    content_urls = Enum.map(extras, & &1.content_url)

    media_dirs_by_path =
      from(f in FilePresence,
        where: f.file_path in ^content_urls,
        select: {f.file_path, f.media_dir}
      )
      |> Repo.all()
      |> Map.new()

    created =
      Enum.reduce(extras, 0, fn extra, count ->
        with media_dir when is_binary(media_dir) <- Map.get(media_dirs_by_path, extra.content_url),
             {:ok, _} <-
               create_extra_file(%{
                 file_path: extra.content_url,
                 media_dir: media_dir,
                 extra_id: extra.id
               }) do
          count + 1
        else
          # No FilePresence (can't resolve media_dir), or the row was created
          # concurrently by a rescan re-ingest — either way, leave it.
          _ -> count
        end
      end)

    %{created: created}
  end

  # ---------------------------------------------------------------------------
  # Season
  # ---------------------------------------------------------------------------

  def list_seasons, do: Repo.all(Season)

  def fetch_season(id) do
    case Repo.get(Season, id) do
      nil -> {:error, :not_found}
      season -> {:ok, season}
    end
  end

  def create_season(attrs) do
    Repo.insert(Season.create_changeset(attrs))
  end

  def create_season!(attrs), do: Repo.bang!(create_season(attrs))

  def destroy_season(season), do: Repo.delete(season)
  def destroy_season!(season), do: Writes.destroy!(season)

  def find_or_create_season_for_tv_series(attrs) do
    Writes.find_or_insert_by(
      Season,
      [
        tv_series_id: Writes.attr(attrs, :tv_series_id),
        season_number: Writes.attr(attrs, :season_number)
      ],
      attrs
    )
  end

  def list_seasons_for_tv_series(tv_series_id) do
    Repo.all(from(s in Season, where: s.tv_series_id == ^tv_series_id))
  end

  # ---------------------------------------------------------------------------
  # Episode
  # ---------------------------------------------------------------------------

  def list_episodes, do: Repo.all(Episode)

  def list_episodes_for_season(season_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    # Preload the WatchedFile chain so the virtual `content_url`
    # populates on the returned Episode structs (Library Schema v2
    # Phase 2 Task I).
    full_preloads = List.flatten([@leaf_file_path_preload | preloads])

    from(e in Episode, where: e.season_id == ^season_id)
    |> Repo.all()
    |> Repo.preload(full_preloads)
    |> Enum.map(&ContentUrls.populate/1)
  end

  def fetch_episode(id) do
    case Repo.get(Episode, id) do
      nil ->
        {:error, :not_found}

      episode ->
        # Populate the virtual `content_url` so consumers (`Resolver`,
        # detail panel) that read `episode.content_url` post-fetch see
        # the on-disk path (Library Schema v2 Phase 2 Task I).
        {:ok, episode |> Repo.preload(@leaf_file_path_preload) |> ContentUrls.populate()}
    end
  end

  def find_or_create_episode(attrs) do
    Writes.find_or_insert_by(
      Episode,
      [season_id: Writes.attr(attrs, :season_id), episode_number: Writes.attr(attrs, :episode_number)],
      attrs
    )
  end

  @doc """
  Finds the Episode under `tv_series_id` linked to `file_path` via its
  `PlayableItem → WatchedFile` chain. After Library Schema v2 Phase 2
  Task I dropped `Episode.content_url`, this lookup goes through the
  WatchedFile join — `WatchedFile.file_path` is the sole source of truth
  for "the file on disk for this Episode."

  Returns `nil` when no Episode has been linked to `file_path` — callers
  must handle the missing-row case (typically an ingest race or a stale
  event).
  """
  @spec find_episode_by_path(Ecto.UUID.t(), String.t()) :: Episode.t() | nil
  def find_episode_by_path(tv_series_id, file_path)
      when is_binary(tv_series_id) and is_binary(file_path) do
    Repo.one(
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        join: pi in PlayableItem,
        on: pi.container_id == e.id and pi.container_type == :episode,
        join: w in WatchedFile,
        on: w.playable_item_id == pi.id,
        where: s.tv_series_id == ^tv_series_id and w.file_path == ^file_path,
        limit: 1
      )
    )
  end

  @doc """
  Finds the child Movie under `movie_series_id` linked to `file_path`
  via its `PlayableItem → WatchedFile` chain. The collection-child
  counterpart of `find_episode_by_path/2`.
  """
  @spec find_movie_by_path(Ecto.UUID.t(), String.t()) :: Movie.t() | nil
  def find_movie_by_path(movie_series_id, file_path)
      when is_binary(movie_series_id) and is_binary(file_path) do
    Repo.one(
      from(m in Movie,
        join: pi in PlayableItem,
        on: pi.container_id == m.id and pi.container_type == :movie,
        join: w in WatchedFile,
        on: w.playable_item_id == pi.id,
        where: m.movie_series_id == ^movie_series_id and w.file_path == ^file_path,
        limit: 1
      )
    )
  end

  @doc """
  Finds the Episode under `tv_series_id` with `(season_number, episode_number)`.
  Used by callers that have the (season_number, episode_number) tuple
  directly — `Library.Inbound`'s `leaf_container_for` walks this path
  because at file-link time the WatchedFile doesn't exist yet (it's
  being created in the same flow).
  """
  @spec find_episode_by_season_episode(Ecto.UUID.t(), integer(), integer()) :: Episode.t() | nil
  def find_episode_by_season_episode(tv_series_id, season_number, episode_number)
      when is_binary(tv_series_id) and is_integer(season_number) and is_integer(episode_number) do
    Repo.one(
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        where:
          s.tv_series_id == ^tv_series_id and
            s.season_number == ^season_number and
            e.episode_number == ^episode_number,
        limit: 1
      )
    )
  end

  def create_episode(attrs) do
    Repo.insert(Episode.create_changeset(attrs))
  end

  def create_episode!(attrs), do: Repo.bang!(create_episode(attrs))

  # ---------------------------------------------------------------------------
  # ChangeEntry
  # ---------------------------------------------------------------------------

  def create_change_entry(attrs) do
    Repo.insert(ChangeEntry.create_changeset(attrs))
  end

  def create_change_entry!(attrs), do: Repo.bang!(create_change_entry(attrs))

  def list_recent_changes(limit, since) do
    query =
      from(c in ChangeEntry,
        order_by: [{:desc, c.inserted_at}, {:desc, fragment("rowid")}],
        limit: ^limit
      )

    query =
      if since do
        from(c in query, where: c.inserted_at >= ^since)
      else
        query
      end

    Repo.all(query)
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  defdelegate broadcast_entities_changed(entity_ids), to: MediaCentaur.Library.Helpers

  # ---------------------------------------------------------------------------
  # HomeLive Facade — query + display-shaping lives in Library.HomeFeed;
  # these delegators keep the context's public API stable for the Views.*
  # projections and Status.
  # ---------------------------------------------------------------------------

  @doc "See `MediaCentaur.Library.HomeFeed.list_in_progress/1` (Continue Watching)."
  def list_in_progress(opts \\ []), do: HomeFeed.list_in_progress(opts)

  @doc "See `MediaCentaur.Library.HomeFeed.list_recently_added/1`."
  def list_recently_added(opts \\ []), do: HomeFeed.list_recently_added(opts)

  @doc "See `MediaCentaur.Library.HomeFeed.list_hero_candidates/1`."
  def list_hero_candidates(opts \\ []), do: HomeFeed.list_hero_candidates(opts)

  @doc """
  Library-wide entity, episode, file and image counts for the Status page's
  operational dashboard.

  A `Movie` belonging to a `MovieSeries` is part of a collection, not a
  standalone title, so it is excluded from the `:movie` count. That
  distinction is the library's own rule and lives here, not in the caller.
  """
  @spec stats() :: %{
          episodes: non_neg_integer(),
          files: non_neg_integer(),
          images: non_neg_integer(),
          by_type: %{
            movie: non_neg_integer(),
            tv_series: non_neg_integer(),
            movie_series: non_neg_integer(),
            video_object: non_neg_integer()
          }
        }
  def stats do
    %{
      episodes: count_rows(Episode),
      files: count_rows(WatchedFile),
      images: count_rows(Image),
      by_type: %{
        movie: Repo.one(from(m in Movie, where: is_nil(m.movie_series_id), select: count(m.id))),
        tv_series: count_rows(TVSeries),
        movie_series: count_rows(MovieSeries),
        video_object: count_rows(VideoObject)
      }
    }
  end

  defp count_rows(schema), do: Repo.one(from(record in schema, select: count(record.id)))

  # ---------------------------------------------------------------------------
  # Media track overrides (per-entity audio/subtitle preferences)
  # ---------------------------------------------------------------------------

  @doc """
  Fetch the override for an entity, or `nil` if none has been recorded.
  """
  @spec get_media_track_override(MediaTrackOverride.owner_type(), Ecto.UUID.t()) ::
          MediaTrackOverride.t() | nil
  def get_media_track_override(owner_type, owner_id) when is_atom(owner_type) and is_binary(owner_id) do
    Repo.get_by(MediaTrackOverride, owner_type: owner_type, owner_id: owner_id)
  end

  @doc """
  Insert a new override row for an entity, or update the existing one in
  place. Returns `{:ok, override}` or `{:error, changeset}`.

  The override row stores the user's full diverges-from-policy state for
  the entity: any of the four override fields may be `nil` (audio/subs
  follow policy) or set (override that aspect to this language). Callers
  are responsible for computing the diff against the policy choice
  before invoking — this function just persists what it's given.
  """
  @spec upsert_media_track_override(MediaTrackOverride.owner_type(), Ecto.UUID.t(), map()) ::
          {:ok, MediaTrackOverride.t()} | {:error, Ecto.Changeset.t()}
  def upsert_media_track_override(owner_type, owner_id, attrs)
      when is_atom(owner_type) and is_binary(owner_id) and is_map(attrs) do
    attrs =
      attrs
      |> Map.put(:owner_type, owner_type)
      |> Map.put(:owner_id, owner_id)

    # Guard against unknown owner_types reaching the Repo — Ecto.Enum
    # would raise an `Ecto.Query.CastError` from the existence check
    # before the changeset has a chance to surface a clean validation
    # error to the caller.
    if owner_type in MediaTrackOverride.owner_types() do
      case get_media_track_override(owner_type, owner_id) do
        nil -> Repo.insert(MediaTrackOverride.changeset(%MediaTrackOverride{}, attrs))
        existing -> Repo.update(MediaTrackOverride.changeset(existing, attrs))
      end
    else
      {:error, MediaTrackOverride.changeset(%MediaTrackOverride{}, attrs)}
    end
  end

  @doc """
  Delete the override row for an entity. Returns `:ok` whether or not
  an override existed — callers don't need to check first.
  """
  @spec clear_media_track_override(MediaTrackOverride.owner_type(), Ecto.UUID.t()) :: :ok
  def clear_media_track_override(owner_type, owner_id)
      when is_atom(owner_type) and is_binary(owner_id) do
    case get_media_track_override(owner_type, owner_id) do
      nil ->
        :ok

      override ->
        {:ok, _} = Repo.delete(override)
        :ok
    end
  end

  @doc """
  Decorate a modal entity-map with its per-entity track override under
  the `:track_override` key. Only movies and TV series can own an
  override; every other container kind (`:movie_series`, `:video_object`)
  — and any map missing `:id`/`:type` — gets `nil`.

  Called by the modal-entry builders right after
  `Views.DetailItem.to_entity_map/1`, so both construction paths
  (`load_modal_entry/1` for movies + refreshes, `SeriesDetail.compose/1`
  for TV-series initial opens) carry the override without the detail UI
  issuing a second context round-trip.
  """
  @spec put_track_override(map()) :: map()
  def put_track_override(%{id: id, type: type} = entity)
      when type in [:movie, :tv_series] and is_binary(id) do
    Map.put(entity, :track_override, get_media_track_override(type, id))
  end

  def put_track_override(entity) when is_map(entity), do: Map.put(entity, :track_override, nil)

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Stamps Library.FilePresence for the given path so the upcoming
  # WatchedFile/ExtraFile insert satisfies its NOT-NULL changeset
  # validation (and, after the matching schema migration, its FK
  # constraint). Falls through unchanged when either input is missing
  # or blank so the downstream changeset surfaces the missing-field
  # error rather than crashing inside `FilePresence.stamp/3`.
  defp ensure_file_presence_id(attrs, file_path, media_dir)
       when is_binary(file_path) and byte_size(file_path) > 0 and is_binary(media_dir) and
              byte_size(media_dir) > 0 do
    presence = FilePresence.stamp(file_path, media_dir)
    Map.put(attrs, :file_presence_id, presence.id)
  end

  defp ensure_file_presence_id(attrs, _file_path, _media_dir), do: attrs
end
