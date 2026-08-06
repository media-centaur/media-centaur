defmodule MediaCentaur.Library.Views.Detail do
  @moduledoc """
  ETS-backed projection of detail-modal view-models keyed by
  `PlayableItem` UUID (ADR-041, Library Schema v2 Phase 3 Task B,
  expanded Phase 3.2).

  One row per `Library.PlayableItem`. Each row carries the container
  metadata, embedded cast/crew, extras, external_ids, the `:present?`
  flag, and Phase 3.2 additions: `:images`, `:watched_files`,
  `:subtitle_tracks`, `:seasons` (for TV episode rows), `:movies`
  (for MovieSeries constituent rows). Reads bypass the GenServer
  entirely — see `Library.Views.detail/1` and
  `Library.Views.detail_by_container/2`.

  ## Phase 3.2 entity-keyed read paths

  `detail_by_container(:tv_series, id)` and
  `detail_by_container(:movie_series, id)` resolve to the **canonical
  leaf** under the entity — for TV the lowest-position episode of
  season 1 (or whatever's first), for MovieSeries the lowest
  `collection_position` movie. The canonical leaf's row carries the
  full `:seasons` or `:movies` tree, so the modal-open path reads
  one ETS row to render the entire series.

  ## Refresh strategy

  Two flavours:

    * **Full rebuild** at boot via `refresh_cache/0` — walks every
      PlayableItem, groups by top-level entity, builds entity-level
      shared data once per entity (functional sharing — same
      `:seasons` / `:movies` / `:images` reference flows into each
      sibling row).
    * **Partial rebuild** via `handle_message/1` — translates the
      incoming event to the set of affected `playable_item_id`s and
      rebuilds only those rows. Per-PlayableItem partial refresh
      keeps detail rebuilds cheap when only one entity changes.
      Entity-level data is re-fetched per row in partial mode (one
      extra fetch per row); acceptable because partial refresh is
      already row-scoped.

  ## Refresh triggers

    * `library:updates` — `EntitiesChanged{entity_ids:}` rebuilds the
      rows for each affected entity's PlayableItems.
    * `library:availability` — drive-mount / drive-unmount: full rebuild
      (presence flips can affect many rows; the cheap path is to
      reconcile the whole table).

  ## Storage

    * `:library_view_detail` — `:set`, `:public`, `:named_table`,
      `:read_concurrency, true`. Keyed by `playable_item_id`.

  ## Broadcast contract

  Emits `{:library_view_updated, :detail, playable_item_id}` on the
  `library:views` topic for each row touched. The 3-tuple shape lets
  DetailLive subscribe to only its current PlayableItem and ignore
  unrelated updates. This is intentionally distinct from Browse's
  2-tuple `{:library_view_updated, :browse}`, which discriminates the
  whole-table refresh.
  """
  @behaviour MediaCentaur.Cache

  import Ecto.Query

  alias MediaCentaur.Library
  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Library.CollectionArtwork
  alias MediaCentaur.Library.Episode
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Library.Movie
  alias MediaCentaur.Library.MovieSeries
  alias MediaCentaur.Library.PlayableItem
  alias MediaCentaur.Library.PresentableQueries
  alias MediaCentaur.Library.Season
  alias MediaCentaur.Library.TVSeries
  alias MediaCentaur.Library.Views.DetailItem
  alias MediaCentaur.Library.VideoObject
  alias MediaCentaur.Library.WatchedFile
  alias MediaCentaur.Repo
  alias MediaCentaur.Subtitles
  alias MediaCentaur.Topics

  @table :library_view_detail

  # Secondary index mapping `{container_type, container_id_or_parent_id}`
  # to the canonical `playable_item_id` for that entity. Lets
  # `read_by_container/2` resolve a container UUID to its canonical
  # PlayableItem row in two O(1) ETS lookups instead of the prior
  # `:ets.select` table scan (which scanned every PlayableItem in the
  # library on each TV-series or movie-series modal open). Maintained on
  # full and partial refreshes alongside the main `@table`.
  @canonical_table :library_view_detail_canonical

  # Entity-level payload, stored once per `{entity_type, entity_id}` grouping
  # instead of once per row.
  #
  # ETS deep-copies every term on `:ets.insert/2`, so the functional sharing
  # the build path achieves (one `shared` map flowing into every sibling row)
  # is destroyed at the table boundary. Storing `:cast` and `:seasons` inline
  # meant a 900-member series cast was physically copied into each of its
  # episodes' rows: measured at 219 MB across 765 rows for 41 distinct cast
  # lists and 18 distinct season trees. Splitting them out reduces the same
  # projection to ~15 MB and drops the per-read heap copy from ~180 KB to a
  # few hundred bytes for the rows that don't need the entity payload.
  #
  # Rows are deflated on write (`deflate/1`) and re-joined on read
  # (`inflate/1`), so `DetailItem` reaches every consumer fully populated —
  # the split is invisible above `read/1` and `read_by_container/2`.
  @shared_table :library_view_detail_shared

  @shared_fields [:cast, :crew, :seasons, :movies, :images, :external_ids]

  @impl MediaCentaur.Cache
  def subscribe do
    Topics.subscribe(Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentaur.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _dir, _state}), do: true
  def relevant?(_), do: false

  @impl MediaCentaur.Cache
  def refresh_cache do
    ensure_table()

    items = build_all_items()

    :ets.delete_all_objects(@table)
    :ets.delete_all_objects(@canonical_table)
    :ets.delete_all_objects(@shared_table)

    Enum.each(items, fn item ->
      {light, shared_entry} = deflate(item)
      :ets.insert(@shared_table, shared_entry)
      :ets.insert(@table, {item.playable_item_id, light})
    end)

    items
    |> build_canonical_entries()
    |> Enum.each(&:ets.insert(@canonical_table, &1))

    # One event for the whole table. Broadcasting per row made every
    # subscriber re-read once per row in the library to converge on data it
    # already had — 765 reads and 765 re-renders per rebuild on a real
    # library. Per-row 3-tuples remain the contract for *partial* refresh,
    # where the id genuinely discriminates.
    broadcast_row(:all)

    :ok
  end

  @impl MediaCentaur.Cache
  def handle_message({:entities_changed, %{entity_ids: ids}}) when is_list(ids) do
    ensure_table()

    case Library.PlayableItems.ids_for_entities(ids) do
      [] ->
        # The entity may have been deleted — its PlayableItems are gone.
        # Sweep any stale rows from the table that point at these
        # container_ids. We can't ask the DB; rely on the ETS index.
        Enum.each(ids, &delete_rows_for_container_id/1)
        :ok

      playable_item_ids ->
        Enum.each(playable_item_ids, &rebuild_row/1)
        # Also sweep rows whose PlayableItems no longer exist for the
        # given container ids (e.g. partial deletion).
        Enum.each(ids, fn container_id ->
          Enum.each(stale_rows_for_container_id(container_id, playable_item_ids), &delete_row/1)
        end)

        :ok
    end
  end

  def handle_message({:availability_changed, _dir, _state}) do
    # A drive mounting or unmounting changes exactly one field — `:present?`.
    # Rebuilding the whole projection to flip a boolean re-ran every
    # container query and re-copied every row (measured at 276 ms on a
    # 765-row library), which a flapping network mount could trigger
    # repeatedly. Recompute presence from one query and patch the affected
    # rows in place instead.
    ensure_table()
    reconcile_presence()
  end

  def handle_message(_msg), do: :ok

  @doc """
  Read the projection for a single `playable_item_id`. Returns the
  cached `DetailItem` or nil when no row exists.

  Falls back to a live build when the ETS table is absent, OR when the
  table exists but the requested row is missing — both cover test
  mode (Cache.Worker not started, refresh cadence uncoordinated with
  test fixtures) and the brief window in production between an
  entity's creation and the projection's next refresh.
  """
  @spec read(Ecto.UUID.t()) :: DetailItem.t() | nil
  def read(playable_item_id) when is_binary(playable_item_id) do
    case :ets.whereis(@table) do
      :undefined ->
        build_item_for_playable_item_id(playable_item_id)

      _ref ->
        case read_from_ets(playable_item_id) do
          nil -> build_item_for_playable_item_id(playable_item_id)
          %DetailItem{} = item -> item
        end
    end
  end

  def read(_), do: nil

  @doc """
  Read the projection by container UUID. Resolves to the canonical
  PlayableItem's row:

    * `:movie`, `:video_object` — single-leaf containers; returns the
      sole (or position=1) PlayableItem's row.
    * `:tv_series` (Phase 3.2) — returns the canonical episode's row,
      which carries the full `:seasons` tree for the series. The
      canonical episode is the lowest-position PlayableItem under the
      series (typically S01E01).
    * `:movie_series` (Phase 3.2) — returns the lowest-`collection_position`
      constituent movie's row, which carries the full `:movies` list.

  Returns nil for `:episode` — callers should hold the
  `playable_item_id` directly via `read/1`.
  """
  @spec read_by_container(atom(), Ecto.UUID.t()) :: DetailItem.t() | nil
  def read_by_container(container_type, container_id)
      when container_type in [:movie, :video_object, :tv_series, :movie_series] and
             is_binary(container_id) do
    case :ets.whereis(@table) do
      :undefined ->
        build_item_for_container(container_type, container_id)

      _ref ->
        case read_from_ets_by_container(container_type, container_id) do
          nil -> build_item_for_container(container_type, container_id)
          %DetailItem{} = item -> item
        end
    end
  end

  def read_by_container(_type, _id), do: nil

  # --- ETS read paths ---

  defp read_from_ets(playable_item_id) do
    case :ets.lookup(@table, playable_item_id) do
      [{^playable_item_id, %DetailItem{} = item}] -> inflate(item)
      _ -> nil
    end
  end

  defp read_from_ets_by_container(container_type, container_id) do
    case :ets.whereis(@canonical_table) do
      :undefined ->
        nil

      _ref ->
        with [{_key, pi_id}] <- :ets.lookup(@canonical_table, {container_type, container_id}),
             [{^pi_id, %DetailItem{} = item}] <- :ets.lookup(@table, pi_id) do
          inflate(item)
        else
          _ -> nil
        end
    end
  end

  # --- Presence reconciliation (drive mount / unmount) ---

  # Recomputes only the file-derived fields — `:present?`, `:watched_files`,
  # `:subtitle_tracks` — for every stored row, from three batched queries
  # rather than the full `build_all_items/0` pipeline. Presence is structural
  # (`WatchedFile.file_presence_id` cascade-deletes with `FilePresence`), so
  # a drive flip changes these three and nothing else: not the grouping, not
  # the containers, not the entity payload.
  #
  # Rows are read and written in their deflated form so the entity payload is
  # never re-copied. One `:all` broadcast covers the batch.
  defp reconcile_presence do
    rows = :ets.tab2list(@table)
    playable_items = Enum.map(rows, fn {_id, item} -> %PlayableItem{id: item.playable_item_id} end)

    watched_files = build_watched_files_map(playable_items)
    subtitle_tracks = build_subtitle_tracks_map(watched_files)
    media_infos = build_media_infos_map(watched_files)

    changed? =
      Enum.reduce(rows, false, fn {id, %DetailItem{} = item}, acc ->
        files = Map.get(watched_files, id, [])

        updated = %{
          item
          | present?: files != [],
            watched_files: build_watched_files(files, media_infos),
            subtitle_tracks: build_subtitle_tracks(Map.get(subtitle_tracks, id, []))
        }

        if updated == item do
          acc
        else
          :ets.insert(@table, {id, updated})
          true
        end
      end)

    if changed?, do: broadcast_row(:all)

    :ok
  end

  # --- Shared entity payload split (see @shared_table) ---

  # Splits a fully-built row into the per-row remainder and the entity-level
  # payload, returning both ready for `:ets.insert/2`. Rows sharing a
  # `shared_key` write the same entity entry — last write wins, and they are
  # all built from the same source, so the value is identical.
  defp deflate(%DetailItem{shared_key: key} = item) do
    shared = Map.take(Map.from_struct(item), @shared_fields)
    light = Enum.reduce(@shared_fields, item, &Map.put(&2, &1, nil))
    {light, {key, shared}}
  end

  # Re-attaches the entity payload to a stored row. Degrades to the row as
  # stored — entity fields nil, the same shape a metadata-less entity
  # produces — rather than raising, in the two cases where the payload is
  # unavailable: a missing entry (entity deleted between the row write and
  # this read), and a missing table (the two tables have independent
  # lifetimes; a dev hot reload can take one down while the other survives).
  defp inflate(%DetailItem{shared_key: nil} = item), do: item

  defp inflate(%DetailItem{shared_key: key} = item) do
    case :ets.whereis(@shared_table) do
      :undefined ->
        item

      _ref ->
        case :ets.lookup(@shared_table, key) do
          [{^key, shared}] -> struct(item, shared)
          _ -> item
        end
    end
  end

  # --- Canonical-index population ---

  # Picks the canonical PlayableItem row per `{container_type, container_id}`
  # lookup key from the in-memory DetailItem set. Used by full refresh
  # (`refresh_cache/0`) to bulk-populate the index from already-built
  # items. The output is a list of `{key, playable_item_id}` tuples
  # ready for `:ets.insert/2`.
  defp build_canonical_entries(items) do
    items
    |> Enum.flat_map(&canonical_entries_for_row/1)
    |> Enum.group_by(fn {key, _sort, _pi_id} -> key end)
    |> Enum.map(fn {key, entries} ->
      {_key, _sort, pi_id} = Enum.min_by(entries, fn {_key, sort, _pi_id} -> sort end)
      {key, pi_id}
    end)
  end

  # A row contributes to:
  #   * its own leaf key for `:movie` / `:video_object` lookups
  #     (`{:movie, movie_id}` / `{:video_object, vo_id}`); episodes do
  #     not — `read_by_container(:episode, _)` is intentionally not
  #     supported.
  #   * its parent series key for series-rooted lookups
  #     (`{:tv_series, series_id}` / `{:movie_series, ms_id}`).
  #
  # Sort key disambiguates siblings: lowest sort wins. Order chosen to
  # match the prior `:ets.select` + Enum.min_by behaviour so the
  # canonical row is identical to what callers got before the index
  # was introduced.
  defp canonical_entries_for_row(%DetailItem{container_type: :movie} = item) do
    leaf_entry =
      {{:movie, item.container_id}, {item.position || 0, item.playable_item_id}, item.playable_item_id}

    series_entry =
      case item.presented_as do
        :movie_series ->
          collection_position = movie_collection_position(item)

          [
            {{:movie_series, item.parent_container_id}, {collection_position, item.playable_item_id},
             item.playable_item_id}
          ]

        _ ->
          []
      end

    [leaf_entry | series_entry]
  end

  defp canonical_entries_for_row(%DetailItem{container_type: :video_object} = item) do
    [
      {{:video_object, item.container_id}, {item.position || 0, item.playable_item_id},
       item.playable_item_id}
    ]
  end

  defp canonical_entries_for_row(
         %DetailItem{container_type: :episode, parent_container_id: tv_series_id} = item
       )
       when not is_nil(tv_series_id) do
    sort = canonical_episode_sort_key(item)
    [{{:tv_series, tv_series_id}, sort, item.playable_item_id}]
  end

  defp canonical_entries_for_row(_), do: []

  defp canonical_episode_sort_key(%DetailItem{
         seasons: seasons,
         container_id: episode_id,
         playable_item_id: pi_id
       }) do
    seasons
    |> List.wrap()
    |> Enum.find_value(nil, fn %DetailItem.Season{season_number: sn, episodes: eps} ->
      case Enum.find(eps, &(&1.episode_id == episode_id)) do
        %DetailItem.Episode{episode_number: en} -> {sn, en, pi_id}
        nil -> nil
      end
    end)
    |> case do
      nil -> {999, 999, pi_id}
      key -> key
    end
  end

  defp movie_collection_position(%DetailItem{
         movies: movies,
         container_id: movie_id,
         playable_item_id: pi_id
       }) do
    case Enum.find(movies || [], &(&1.movie_id == movie_id)) do
      %DetailItem.MovieEntry{collection_position: pos} when is_integer(pos) -> {pos, pi_id}
      _ -> {999, pi_id}
    end
  end

  # --- Build paths ---

  defp build_all_items do
    playable_items = Repo.all(PlayableItem)
    context = build_context(playable_items)

    playable_items
    |> Enum.group_by(&grouping_key(&1, context))
    |> Enum.flat_map(fn {entity_key, items} ->
      shared = build_shared_entity_data(entity_key)

      items
      |> Enum.map(&build_item(&1, shared, entity_key, context))
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp build_item_for_playable_item_id(playable_item_id) do
    case Repo.get(PlayableItem, playable_item_id) do
      nil -> nil
      %PlayableItem{} = item -> build_one(item)
    end
  end

  # Single-item build for the partial-refresh and live-fallback paths.
  # Builds a context scoped to the one item, then runs the same pure
  # `build_item/4` the full rebuild uses — so "build one" and "build all"
  # share one builder and differ only in how the context is loaded.
  defp build_one(%PlayableItem{} = item) do
    context = build_context([item])
    grouping = grouping_key(item, context)
    shared = build_shared_entity_data(grouping)
    build_item(item, shared, grouping, context)
  end

  defp build_item_for_container(:movie, container_id) do
    case Repo.one(
           from(p in PlayableItem,
             where: p.container_type == :movie and p.container_id == ^container_id,
             order_by: [asc: p.position],
             limit: 1
           )
         ) do
      nil ->
        nil

      %PlayableItem{} = item ->
        build_one(item)
    end
  end

  defp build_item_for_container(:video_object, container_id) do
    case Repo.one(
           from(p in PlayableItem,
             where: p.container_type == :video_object and p.container_id == ^container_id,
             order_by: [asc: p.position],
             limit: 1
           )
         ) do
      nil ->
        nil

      %PlayableItem{} = item ->
        build_one(item)
    end
  end

  defp build_item_for_container(:tv_series, tv_series_id) do
    # Canonical episode = lowest (season_number, episode_number) under
    # the series. Build that PlayableItem's row.
    query =
      from(p in PlayableItem,
        join: e in Episode,
        on: e.id == p.container_id and p.container_type == :episode,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id == ^tv_series_id,
        order_by: [asc: s.season_number, asc: e.episode_number, asc: p.position],
        limit: 1,
        select: p
      )

    case Repo.one(query) do
      nil ->
        nil

      %PlayableItem{} = item ->
        build_one(item)
    end
  end

  defp build_item_for_container(:movie_series, movie_series_id) do
    # Canonical = lowest collection_position movie in the series.
    query =
      from(p in PlayableItem,
        join: m in Movie,
        on: m.id == p.container_id and p.container_type == :movie,
        where: m.movie_series_id == ^movie_series_id,
        order_by: [asc: m.position, asc: p.position],
        limit: 1,
        select: p
      )

    case Repo.one(query) do
      nil ->
        nil

      %PlayableItem{} = item ->
        build_one(item)
    end
  end

  defp build_item_for_container(_, _), do: nil

  # --- Context: the pre-loaded data the pure builders read from ---

  # A `context` holds every per-item datum the item builder needs, keyed
  # for O(1) lookup. Constructing it is the ONLY place the build path
  # queries — `grouping_key/2` and `build_item/4` are pure functions over
  # it. Built once for the whole table on full refresh, or for a single
  # item on partial refresh; that is what keeps the full rebuild free of
  # per-item N+1 queries.
  defp build_context(playable_items) do
    watched_files = build_watched_files_map(playable_items)

    %{
      grouping: build_grouping_map(playable_items),
      containers: build_container_map(playable_items),
      watched_files: watched_files,
      subtitle_tracks: build_subtitle_tracks_map(watched_files),
      media_infos: build_media_infos_map(watched_files)
    }
  end

  # Probed technical metadata for every file in the set, one query,
  # keyed by path (see `Library.FileMediaInfo`).
  defp build_media_infos_map(watched_files_by_pi_id) do
    watched_files_by_pi_id
    |> Map.values()
    |> List.flatten()
    |> Enum.map(& &1.file_path)
    |> Library.MediaInfo.by_paths()
  end

  defp grouping_key(%PlayableItem{id: id}, context), do: Map.fetch!(context.grouping, id)

  # --- Grouping: top-level entity key per PlayableItem, batched ---

  # `grouping_key` returns the top-level entity identifier — the thing the
  # modal opens by. For episodes that's `(:tv_series, series_id)`; for
  # movies under a present collection that's `(:movie_series, ms_id)`; for
  # everything else the leaf container itself. The three lookups it needs
  # (episode→series, movie→series, and which collections have 2+ present
  # movies) load in bulk here, then resolve per item via the pure
  # `compute_grouping_key/4`.
  defp build_grouping_map(playable_items) do
    series_by_episode = series_by_episode_map(playable_items)
    series_by_movie = series_by_movie_map(playable_items)
    multi_present = multi_present_series_set(series_by_movie)

    Map.new(playable_items, fn item ->
      {item.id, compute_grouping_key(item, series_by_episode, series_by_movie, multi_present)}
    end)
  end

  defp series_by_episode_map(playable_items) do
    episode_ids =
      for %PlayableItem{container_type: :episode, container_id: id} <- playable_items, do: id

    if episode_ids == [] do
      %{}
    else
      Map.new(
        Repo.all(
          from(e in Episode,
            join: s in Season,
            on: s.id == e.season_id,
            where: e.id in ^episode_ids,
            select: {e.id, s.tv_series_id}
          )
        )
      )
    end
  end

  defp series_by_movie_map(playable_items) do
    movie_ids =
      for %PlayableItem{container_type: :movie, container_id: id} <- playable_items, do: id

    if movie_ids == [] do
      %{}
    else
      from(m in Movie, where: m.id in ^movie_ids, select: {m.id, m.movie_series_id})
      |> Repo.all()
      |> Map.new()
    end
  end

  # The hoist set: movie_series ids with 2+ present constituent movies.
  # Membership flips a constituent movie's grouping from `{:movie, _}` to
  # `{:movie_series, _}` — the same rule `collection_multi_present?`
  # encoded per movie, now resolved for every collection in one query.
  defp multi_present_series_set(series_by_movie) do
    movie_series_ids = series_by_movie |> Map.values() |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if movie_series_ids == [] do
      MapSet.new()
    else
      movie_series_ids
      |> PresentableQueries.present_movie_counts()
      |> Repo.all()
      |> Enum.filter(fn {_ms_id, count} -> count >= 2 end)
      |> MapSet.new(fn {ms_id, _count} -> ms_id end)
    end
  end

  defp compute_grouping_key(
         %PlayableItem{container_type: :episode, container_id: episode_id},
         series_by_episode,
         _series_by_movie,
         _multi_present
       ) do
    case Map.get(series_by_episode, episode_id) do
      nil -> {:orphan_episode, episode_id}
      tv_series_id -> {:tv_series, tv_series_id}
    end
  end

  defp compute_grouping_key(
         %PlayableItem{container_type: :movie, container_id: movie_id},
         _series_by_episode,
         series_by_movie,
         multi_present
       ) do
    case Map.get(series_by_movie, movie_id) do
      nil ->
        {:movie, movie_id}

      movie_series_id ->
        if MapSet.member?(multi_present, movie_series_id),
          do: {:movie_series, movie_series_id},
          else: {:movie, movie_id}
    end
  end

  defp compute_grouping_key(%PlayableItem{container_type: type, container_id: id}, _, _, _),
    do: {type, id}

  # `shared_entity_data` holds the per-entity slices flowed identically
  # into every sibling row (cost paid once; references shared).
  defp build_shared_entity_data({:tv_series, tv_series_id}) do
    %{
      images: list_images(:tv_series, tv_series_id),
      seasons: build_seasons_for_tv_series(tv_series_id),
      movies: nil
    }
  end

  defp build_shared_entity_data({:movie_series, movie_series_id}) do
    %{
      images:
        CollectionArtwork.effective_images(
          list_images(:movie_series, movie_series_id),
          child_movie_images(movie_series_id)
        ),
      seasons: nil,
      movies: build_movies_for_movie_series(movie_series_id)
    }
  end

  defp build_shared_entity_data({:movie, movie_id}) do
    %{images: list_images(:movie, movie_id), seasons: nil, movies: nil}
  end

  defp build_shared_entity_data({:video_object, video_object_id}) do
    %{images: list_images(:video_object, video_object_id), seasons: nil, movies: nil}
  end

  defp build_shared_entity_data({:orphan_episode, _}) do
    %{images: [], seasons: nil, movies: nil}
  end

  defp build_shared_entity_data(_), do: %{images: [], seasons: nil, movies: nil}

  defp build_item(
         %PlayableItem{container_type: type, container_id: cid} = item,
         shared,
         grouping,
         context
       ) do
    case Map.get(context.containers, {type, cid}) do
      nil ->
        nil

      container ->
        presented_as = presented_as_from_grouping(grouping)
        watched_files = Map.get(context.watched_files, item.id, [])
        subtitle_tracks = Map.get(context.subtitle_tracks, item.id, [])
        # `parent_*` always reads the full leaf container (so a hoisted movie
        # keeps its collection reference for the badge). The `container_*`
        # metadata reads `display`, which for a movie presented as itself is
        # the leaf Movie with its collection link dropped — that makes
        # `top_level_container/2` resolve to the Movie, so the facets are the
        # movie's own. For a collection-presented movie, `display` is the
        # full leaf and `top_level_container/2` promotes to the MovieSeries.
        display = display_container(type, presented_as, container)
        # Resolve the top-level container (episode→series, collection-movie→
        # series) once per row; the `container_*` metadata fields all read from
        # it, so recomputing it per field was ~18× redundant work per row.
        tlc = top_level_container(type, display)
        external_ids = Map.get(tlc, :external_ids)

        %DetailItem{
          playable_item_id: item.id,
          container_type: type,
          presented_as: presented_as,
          container_id: cid,
          name: leaf_name(type, item, container),
          position: item.position,
          duration_seconds: item.duration_seconds,
          date_published: leaf_date_published(type, container),
          description: leaf_description(type, container),
          parent_container_type: parent_container_type(type, container),
          parent_container_id: parent_container_id(type, container),
          parent_container_name: parent_container_name(type, container),
          container_name: Map.get(tlc, :name),
          container_description: Map.get(tlc, :description),
          container_date_published: Map.get(tlc, :date_published),
          container_url: Map.get(tlc, :url),
          container_tagline: Map.get(tlc, :tagline),
          container_genres: Map.get(tlc, :genres),
          container_studio: Map.get(tlc, :studio),
          container_country_code: Map.get(tlc, :country_code),
          container_original_language: Map.get(tlc, :original_language),
          container_network: Map.get(tlc, :network),
          container_status: Map.get(tlc, :status),
          container_duration_seconds: Map.get(tlc, :duration_seconds),
          container_content_rating: Map.get(tlc, :content_rating),
          container_aggregate_rating: Map.get(tlc, :aggregate_rating_value),
          container_vote_count: Map.get(tlc, :vote_count),
          container_number_of_seasons: Map.get(tlc, :number_of_seasons),
          # Director reads the raw `display` (a per-Movie field), NOT the
          # promoted top-level container — see `container_director/2`.
          container_director: container_director(type, display),
          shared_key: grouping,
          cast: Map.get(tlc, :cast),
          crew: Map.get(tlc, :crew),
          extras: Map.get(tlc, :extras),
          external_ids: external_ids,
          imdb_id: external_id_value(external_ids, "imdb"),
          tmdb_id: external_id_value(external_ids, "tmdb"),
          present?: watched_files != [],
          images: shared.images,
          seasons: shared.seasons,
          movies: shared.movies,
          watched_files: build_watched_files(watched_files, context.media_infos),
          subtitle_tracks: build_subtitle_tracks(subtitle_tracks)
        }
    end
  end

  defp presented_as_from_grouping({:movie, _}), do: :movie
  defp presented_as_from_grouping({:movie_series, _}), do: :movie_series
  defp presented_as_from_grouping({:tv_series, _}), do: :tv_series
  defp presented_as_from_grouping({:video_object, _}), do: :video_object
  defp presented_as_from_grouping({:orphan_episode, _}), do: :tv_series

  # When a Movie is presented as itself, drop its collection link so the
  # `container_*` helpers (via `top_level_container/2`) read the Movie's own
  # metadata instead of bubbling up to the MovieSeries. Every other case
  # keeps the full leaf container.
  defp display_container(:movie, :movie, %Movie{} = movie), do: %{movie | movie_series: nil}
  defp display_container(_type, _presented_as, container), do: container

  defp rebuild_row(playable_item_id) do
    old_keys = canonical_keys_for_stored_row(playable_item_id)

    case build_item_for_playable_item_id(playable_item_id) do
      nil ->
        :ets.delete(@table, playable_item_id)
        Enum.each(old_keys, &recompute_canonical_for_key/1)
        broadcast_row(playable_item_id)

      %DetailItem{} = item ->
        {light, shared_entry} = deflate(item)
        :ets.insert(@shared_table, shared_entry)
        :ets.insert(@table, {playable_item_id, light})

        new_keys =
          item
          |> canonical_entries_for_row()
          |> Enum.map(fn {key, _sort, _pi_id} -> key end)

        (old_keys ++ new_keys)
        |> Enum.uniq()
        |> Enum.each(&recompute_canonical_for_key/1)

        broadcast_row(playable_item_id)
    end
  end

  defp delete_row(playable_item_id) do
    affected_keys = canonical_keys_for_stored_row(playable_item_id)
    :ets.delete(@table, playable_item_id)
    Enum.each(affected_keys, &recompute_canonical_for_key/1)
    broadcast_row(playable_item_id)
  end

  defp canonical_keys_for_stored_row(playable_item_id) do
    case :ets.lookup(@table, playable_item_id) do
      [{^playable_item_id, %DetailItem{} = item}] ->
        item
        |> canonical_entries_for_row()
        |> Enum.map(fn {key, _sort, _pi_id} -> key end)

      _ ->
        []
    end
  end

  # Recomputes the canonical-index entry for one lookup key by walking
  # the main table for matching rows and picking the lowest sort key.
  # Runs only on the write path (refresh / rebuild / delete) — the read
  # path is two O(1) ETS lookups against this index.
  defp recompute_canonical_for_key(key) do
    case canonical_entries_for_key(key) do
      [] ->
        :ets.delete(@canonical_table, key)

      entries ->
        {_key, _sort, pi_id} = Enum.min_by(entries, fn {_key, sort, _pi_id} -> sort end)
        :ets.insert(@canonical_table, {key, pi_id})
    end
  end

  # Returns all canonical-index entries (`{key, sort, pi_id}`) under
  # the given lookup key. Used to pick the canonical at write time.
  defp canonical_entries_for_key({container_type, target_id})
       when container_type in [:movie, :video_object] do
    match_spec = [
      {{:_, %{container_type: container_type, container_id: target_id}}, [], [:"$_"]}
    ]

    @table
    |> :ets.select(match_spec)
    |> Enum.flat_map(fn {_pi_id, item} -> canonical_entries_for_row(item) end)
    |> Enum.filter(fn {key, _sort, _pi_id} -> key == {container_type, target_id} end)
  end

  defp canonical_entries_for_key({:tv_series, tv_series_id}) do
    match_spec = [
      {{:_, %{container_type: :episode, parent_container_id: tv_series_id}}, [], [:"$_"]}
    ]

    @table
    |> :ets.select(match_spec)
    |> Enum.flat_map(fn {_pi_id, item} -> canonical_entries_for_row(item) end)
    |> Enum.filter(fn {key, _sort, _pi_id} -> key == {:tv_series, tv_series_id} end)
  end

  defp canonical_entries_for_key({:movie_series, movie_series_id}) do
    match_spec = [
      {{:_, %{container_type: :movie, parent_container_id: movie_series_id}}, [], [:"$_"]}
    ]

    @table
    |> :ets.select(match_spec)
    |> Enum.flat_map(fn {_pi_id, item} -> canonical_entries_for_row(item) end)
    |> Enum.filter(fn {key, _sort, _pi_id} -> key == {:movie_series, movie_series_id} end)
  end

  defp canonical_entries_for_key(_), do: []

  defp delete_rows_for_container_id(container_id) do
    @table
    |> :ets.select([
      {{:"$1", %{container_id: container_id}}, [], [:"$1"]}
    ])
    |> Enum.each(&delete_row/1)
  end

  defp stale_rows_for_container_id(container_id, live_ids) do
    @table
    |> :ets.select([
      {{:"$1", %{container_id: container_id}}, [], [:"$1"]}
    ])
    |> Enum.reject(&(&1 in live_ids))
  end

  # `playable_item_id` is a row UUID for partial refreshes, or `:all` when
  # the whole table was rebuilt.
  defp broadcast_row(playable_item_id) do
    Topics.publish(
      Topics.library_views(),
      {:library_view_updated, :detail, playable_item_id}
    )
  end

  defp ensure_table do
    Enum.each([@table, @canonical_table, @shared_table], fn table ->
      case :ets.whereis(table) do
        :undefined -> :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
        _ref -> :ok
      end
    end)
  end

  # --- Container fetchers with preloads (batched) ---

  # Bulk-loads every leaf container referenced by the given PlayableItems,
  # one query per container type, keyed by `{type, container_id}` for the
  # builder's O(1) lookup. Replaces the prior per-item `fetch_container/2`,
  # which fired one query per PlayableItem during the full rebuild.
  defp build_container_map(playable_items) do
    container_ids_by_type = Enum.group_by(playable_items, & &1.container_type, & &1.container_id)

    %{}
    |> Map.merge(load_containers(:movie, Map.get(container_ids_by_type, :movie, [])))
    |> Map.merge(load_containers(:episode, Map.get(container_ids_by_type, :episode, [])))
    |> Map.merge(load_containers(:video_object, Map.get(container_ids_by_type, :video_object, [])))
  end

  defp load_containers(_type, []), do: %{}

  defp load_containers(:movie, ids) do
    Map.new(
      Repo.all(
        from(m in Movie,
          where: m.id in ^ids,
          preload: [:extras, :external_ids, movie_series: [:extras, :external_ids]]
        )
      ),
      fn movie -> {{:movie, movie.id}, movie} end
    )
  end

  defp load_containers(:episode, ids) do
    Map.new(
      Repo.all(
        from(e in Episode,
          where: e.id in ^ids,
          preload: [season: [tv_series: [:extras, :external_ids]]]
        )
      ),
      fn episode -> {{:episode, episode.id}, episode} end
    )
  end

  defp load_containers(:video_object, ids) do
    Map.new(
      Repo.all(from(v in VideoObject, where: v.id in ^ids, preload: [:external_ids])),
      fn video_object -> {{:video_object, video_object.id}, video_object} end
    )
  end

  defp load_containers(_type, _ids), do: %{}

  # --- Leaf-level fields ---

  defp leaf_name(:episode, _item, %Episode{name: name}) when is_binary(name) and name != "", do: name

  defp leaf_name(:movie, _item, %Movie{name: name}), do: name
  defp leaf_name(:video_object, _item, %VideoObject{name: name}), do: name
  defp leaf_name(_, %PlayableItem{name: name}, _) when is_binary(name), do: name
  defp leaf_name(_, _item, container), do: Map.get(container, :name)

  defp leaf_date_published(:episode, _), do: nil
  defp leaf_date_published(_, %{date_published: date}), do: date
  defp leaf_date_published(_, _), do: nil

  defp leaf_description(_, %{description: desc}), do: desc
  defp leaf_description(_, _), do: nil

  # --- Parent container resolution ---

  defp parent_container_type(:episode, _), do: :tv_series

  defp parent_container_type(:movie, %Movie{movie_series: %MovieSeries{}}), do: :movie_series

  defp parent_container_type(_, _), do: nil

  defp parent_container_id(:episode, %Episode{season: %Season{tv_series: %TVSeries{id: id}}}), do: id

  defp parent_container_id(:movie, %Movie{movie_series: %MovieSeries{id: id}}), do: id
  defp parent_container_id(_, _), do: nil

  defp parent_container_name(:episode, %Episode{season: %Season{tv_series: %TVSeries{name: name}}}),
    do: name

  defp parent_container_name(:movie, %Movie{movie_series: %MovieSeries{name: name}}), do: name
  defp parent_container_name(_, _), do: nil

  # --- Top-level container resolution. Episode → TVSeries; Movie under
  # a MovieSeries → MovieSeries. Same semantic both paths.

  defp top_level_container(:episode, %Episode{season: %Season{tv_series: %TVSeries{} = series}}),
    do: series

  defp top_level_container(:movie, %Movie{movie_series: %MovieSeries{} = ms}), do: ms
  defp top_level_container(_, container), do: container

  # Year derives from the resolved top-level container's `date_published`.
  # Director is a per-Movie field, NOT a top-level metadata bubble-up.
  # For a multi-child MovieSeries the projection's container is a
  # constituent Movie; the entity-map for the MovieSeries modal must
  # not surface one child's director as the collection's director.
  defp container_director(:movie, %Movie{director: director}), do: director
  defp container_director(_type, _container), do: nil

  defp external_id_value(nil, _), do: nil

  defp external_id_value(external_ids, source) when is_list(external_ids) do
    Enum.find_value(external_ids, fn
      %{source: ^source, external_id: value} -> value
      _ -> nil
    end)
  end

  defp external_id_value(_, _), do: nil

  # --- Phase 3.2: images / seasons / movies / watched_files / subtitles ---

  defp list_images(owner_type, owner_id) do
    Repo.all(
      from(i in Image,
        where: i.owner_type == ^owner_type and i.owner_id == ^owner_id
      )
    )
  end

  # Artwork from a collection's constituent movies, ordered by collection
  # position so the earliest movie is the preferred fallback source. Feeds
  # `CollectionArtwork` so a collection with no TMDB art of its own still
  # renders a poster/backdrop in the detail hero.
  defp child_movie_images(movie_series_id) do
    Repo.all(
      from(i in Image,
        join: m in Movie,
        on: m.id == i.owner_id and i.owner_type == :movie,
        where: m.movie_series_id == ^movie_series_id,
        order_by: [asc: m.position]
      )
    )
  end

  defp build_seasons_for_tv_series(tv_series_id) do
    case load_seasons(tv_series_id) do
      [] -> []
      seasons -> shape_seasons(seasons, load_season_graph(seasons))
    end
  end

  defp load_seasons(tv_series_id) do
    Repo.all(
      from(s in Season,
        where: s.tv_series_id == ^tv_series_id,
        order_by: [asc: s.season_number]
      )
    )
  end

  # Every lookup the shaping pass needs, gathered in a fixed number of
  # queries — three down the season → episode → playable-item chain, then
  # one each for extras and episode stills. Bounded: the query count does
  # not grow with the size of the series, only the row count does.
  defp load_season_graph(seasons) do
    season_ids = Enum.map(seasons, & &1.id)

    episodes =
      Repo.all(
        from(e in Episode,
          where: e.season_id in ^season_ids,
          order_by: [asc: e.episode_number]
        )
      )

    episode_ids = Enum.map(episodes, & &1.id)

    playable_items =
      Repo.all(
        from(p in PlayableItem,
          where: p.container_type == :episode and p.container_id in ^episode_ids
        )
      )

    %{
      episodes_by_season_id: Enum.group_by(episodes, & &1.season_id),
      playable_item_by_episode_id: Map.new(playable_items, &{&1.container_id, &1}),
      watched_files_by_playable_item_id: group_watched_files(Enum.map(playable_items, & &1.id)),
      extras_by_season_id: group_season_extras(season_ids),
      images_by_episode_id: group_episode_images(episode_ids)
    }
  end

  defp group_watched_files([]), do: %{}

  defp group_watched_files(playable_item_ids) do
    from(w in WatchedFile,
      where: w.playable_item_id in ^playable_item_ids,
      order_by: [asc: w.inserted_at, asc: w.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.playable_item_id)
  end

  defp group_season_extras([]), do: %{}

  defp group_season_extras(season_ids) do
    from(extra in MediaCentaur.Library.Extra,
      where: extra.owner_type == :season and extra.owner_id in ^season_ids
    )
    |> Repo.all()
    |> Enum.group_by(& &1.owner_id)
  end

  defp group_episode_images([]), do: %{}

  defp group_episode_images(episode_ids) do
    from(image in Image,
      where: image.owner_type == :episode and image.owner_id in ^episode_ids
    )
    |> Repo.all()
    |> Enum.group_by(& &1.owner_id)
  end

  defp shape_seasons(seasons, graph) do
    Enum.map(seasons, fn season ->
      episodes =
        graph.episodes_by_season_id
        |> Map.get(season.id, [])
        |> Enum.map(&shape_episode(&1, season.season_number, graph))

      %DetailItem.Season{
        season_number: season.season_number,
        name: season.name,
        number_of_episodes: season.number_of_episodes,
        episodes: episodes,
        extras: Map.get(graph.extras_by_season_id, season.id, [])
      }
    end)
  end

  defp shape_episode(episode, season_number, graph) do
    playable_item = Map.get(graph.playable_item_by_episode_id, episode.id)
    files = watched_files_for(graph, playable_item)

    %DetailItem.Episode{
      episode_id: episode.id,
      playable_item_id: playable_item_id(playable_item),
      season_number: season_number,
      episode_number: episode.episode_number,
      name: episode.name,
      description: episode.description,
      date_published: episode.date_published,
      duration_seconds: episode.duration_seconds,
      present?: files != [],
      content_url: files |> List.first() |> file_path(),
      images: Map.get(graph.images_by_episode_id, episode.id, [])
    }
  end

  # An episode with no PlayableItem has never been linked to a file — an
  # ordinary state for a series scraped ahead of the download.
  defp watched_files_for(_graph, nil), do: []

  defp watched_files_for(graph, playable_item) do
    Map.get(graph.watched_files_by_playable_item_id, playable_item.id, [])
  end

  defp playable_item_id(nil), do: nil
  defp playable_item_id(%PlayableItem{id: id}), do: id

  defp group_movie_watched_files([]), do: %{}

  defp group_movie_watched_files(playable_item_ids) do
    from(w in WatchedFile, where: w.playable_item_id in ^playable_item_ids)
    |> Repo.all()
    |> Enum.group_by(& &1.playable_item_id)
  end

  defp file_path(nil), do: nil
  defp file_path(%WatchedFile{file_path: path}), do: path

  defp build_movies_for_movie_series(movie_series_id) do
    movies =
      Repo.all(
        from(m in Movie,
          where: m.movie_series_id == ^movie_series_id,
          order_by: [asc: m.position]
        )
      )

    if movies == [] do
      []
    else
      movie_ids = Enum.map(movies, & &1.id)

      playable_items =
        Repo.all(
          from(p in PlayableItem,
            where: p.container_type == :movie and p.container_id in ^movie_ids
          )
        )

      playable_item_by_movie_id =
        Map.new(playable_items, &{&1.container_id, &1})

      watched_files_by_playable_item_id =
        group_movie_watched_files(Enum.map(playable_items, & &1.id))

      Enum.map(movies, fn movie ->
        playable_item = Map.get(playable_item_by_movie_id, movie.id)

        files =
          case playable_item do
            nil -> []
            item -> Map.get(watched_files_by_playable_item_id, item.id, [])
          end

        first_file = List.first(files)

        %DetailItem.MovieEntry{
          movie_id: movie.id,
          playable_item_id: playable_item_id(playable_item),
          name: movie.name,
          date_published: movie.date_published,
          collection_position: movie.position,
          content_url: first_file && first_file.file_path,
          present?: files != []
        }
      end)
    end
  end

  # Watched files for every PlayableItem in the set, one query, grouped
  # by `playable_item_id` and ordered so the first file is the canonical
  # one. The builder reads presence (`!= []`), the `:watched_files` list,
  # and — via `build_subtitle_tracks_map/1` — the file ids for subtitles
  # all from this single load.
  defp build_watched_files_map(playable_items) do
    playable_item_ids = Enum.map(playable_items, & &1.id)

    if playable_item_ids == [] do
      %{}
    else
      Enum.group_by(
        Repo.all(
          from(w in WatchedFile,
            where: w.playable_item_id in ^playable_item_ids,
            order_by: [asc: w.inserted_at, asc: w.id]
          )
        ),
        & &1.playable_item_id
      )
    end
  end

  # Subtitle tracks per PlayableItem, derived from the already-loaded
  # watched-files map: collect every file id, fetch all tracks in one
  # batch query, then regroup by PlayableItem.
  defp build_subtitle_tracks_map(watched_files_by_pi_id) do
    watched_file_ids =
      watched_files_by_pi_id |> Map.values() |> List.flatten() |> Enum.map(& &1.id)

    tracks_by_file_id = Subtitles.list_tracks_for_files(watched_file_ids)

    Map.new(watched_files_by_pi_id, fn {playable_item_id, files} ->
      tracks = Enum.flat_map(files, fn file -> Map.get(tracks_by_file_id, file.id, []) end)
      {playable_item_id, tracks}
    end)
  end

  defp build_watched_files(watched_files, media_infos_by_path) do
    Enum.map(watched_files, fn file ->
      %DetailItem.WatchedFile{
        path: file.file_path,
        media_dir: file.media_dir,
        media_info: build_media_info(Map.get(media_infos_by_path, file.file_path))
      }
    end)
  end

  defp build_media_info(nil), do: nil

  defp build_media_info(info) do
    Map.take(info, [
      :container_title,
      :duration_seconds,
      :video_codec,
      :width,
      :height,
      :audio_summary
    ])
  end

  defp build_subtitle_tracks(tracks) do
    Enum.map(tracks, fn track ->
      %DetailItem.SubtitleTrack{kind: track.kind, language: track.language, source: track.source}
    end)
  end
end
