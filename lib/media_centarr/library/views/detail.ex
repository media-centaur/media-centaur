defmodule MediaCentarr.Library.Views.Detail do
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
  @behaviour MediaCentarr.Cache

  import Ecto.Query

  alias MediaCentarr.Library
  alias MediaCentarr.Library.Availability
  alias MediaCentarr.Library.Episode
  alias MediaCentarr.Library.Image
  alias MediaCentarr.Library.Movie
  alias MediaCentarr.Library.MovieSeries
  alias MediaCentarr.Library.PlayableItem
  alias MediaCentarr.Library.Season
  alias MediaCentarr.Library.TVSeries
  alias MediaCentarr.Library.Views.DetailItem
  alias MediaCentarr.Library.VideoObject
  alias MediaCentarr.Library.WatchedFile
  alias MediaCentarr.Repo
  alias MediaCentarr.Subtitles
  alias MediaCentarr.Topics

  @table :library_view_detail

  @impl MediaCentarr.Cache
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
    Availability.subscribe()
    :ok
  end

  @impl MediaCentarr.Cache
  def relevant?({:entities_changed, _}), do: true
  def relevant?({:availability_changed, _dir, _state}), do: true
  def relevant?(_), do: false

  @impl MediaCentarr.Cache
  def refresh_cache do
    ensure_table()

    items = build_all_items()

    :ets.delete_all_objects(@table)

    Enum.each(items, fn item ->
      :ets.insert(@table, {item.playable_item_id, item})
      broadcast_row(item.playable_item_id)
    end)

    :ok
  end

  @impl MediaCentarr.Cache
  def handle_message({:entities_changed, %{entity_ids: ids}}) when is_list(ids) do
    ensure_table()

    case Library.playable_item_ids_for_entities(ids) do
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
    # Presence flips can affect many rows; the cheap path is a full
    # rebuild rather than walking every row to recompute `:present?`.
    refresh_cache()
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
      [{^playable_item_id, %DetailItem{} = item}] -> item
      _ -> nil
    end
  end

  defp read_from_ets_by_container(container_type, container_id)
       when container_type in [:movie, :video_object] do
    # Match-spec: rows where (container_type, container_id) matches and
    # position == 1. Returns DetailItems sorted by position; pick the
    # first.
    match_spec = [
      {{:_, %{container_type: container_type, container_id: container_id, position: 1}}, [], [:"$_"]}
    ]

    case :ets.select(@table, match_spec) do
      [{_pi_id, %DetailItem{} = item}] -> item
      [{_pi_id, %DetailItem{} = item} | _] -> item
      _ -> nil
    end
  end

  defp read_from_ets_by_container(:tv_series, tv_series_id) do
    # Find episode rows whose parent_container_id matches. Pick the
    # canonical lowest-position one (S01E01 in well-formed seeds).
    match_spec = [
      {{:_, %{container_type: :episode, parent_container_id: tv_series_id}}, [], [:"$_"]}
    ]

    case :ets.select(@table, match_spec) do
      [] ->
        nil

      rows ->
        rows
        |> Enum.map(fn {_pi_id, item} -> item end)
        |> Enum.min_by(&canonical_episode_sort_key/1)
    end
  end

  defp read_from_ets_by_container(:movie_series, movie_series_id) do
    match_spec = [
      {{:_, %{container_type: :movie, parent_container_id: movie_series_id}}, [], [:"$_"]}
    ]

    case :ets.select(@table, match_spec) do
      [] ->
        nil

      rows ->
        rows
        |> Enum.map(fn {_pi_id, item} -> item end)
        |> Enum.min_by(&canonical_movie_sort_key/1)
    end
  end

  defp canonical_episode_sort_key(%DetailItem{
         seasons: seasons,
         container_id: episode_id,
         playable_item_id: pi_id
       }) do
    # Sort key is THIS row's episode's (season_number, episode_number).
    # The :seasons tree is shared across sibling rows; we look up the
    # episode whose id == this row's container_id to pick a per-row
    # discriminator.
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

  defp canonical_movie_sort_key(%DetailItem{
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

    playable_items
    |> Enum.group_by(&entity_grouping_key/1)
    |> Enum.flat_map(fn {entity_key, items} ->
      shared = build_shared_entity_data(entity_key)

      items
      |> Enum.map(&build_item_for_playable_item(&1, shared))
      |> Enum.reject(&is_nil/1)
    end)
  end

  defp build_item_for_playable_item_id(playable_item_id) do
    case Repo.get(PlayableItem, playable_item_id) do
      nil ->
        nil

      %PlayableItem{} = item ->
        shared = build_shared_entity_data(entity_grouping_key(item))
        build_item_for_playable_item(item, shared)
    end
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
        shared = build_shared_entity_data(entity_grouping_key(item))
        build_item_for_playable_item(item, shared)
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
        shared = build_shared_entity_data(entity_grouping_key(item))
        build_item_for_playable_item(item, shared)
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
        shared = build_shared_entity_data(entity_grouping_key(item))
        build_item_for_playable_item(item, shared)
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
        shared = build_shared_entity_data(entity_grouping_key(item))
        build_item_for_playable_item(item, shared)
    end
  end

  defp build_item_for_container(_, _), do: nil

  # `entity_grouping_key` returns the top-level entity identifier — the
  # thing the modal opens by. For episodes that's `(:tv_series,
  # series_id)`; for movies-under-MovieSeries that's `(:movie_series,
  # ms_id)`; for everything else that's the leaf container itself.
  defp entity_grouping_key(%PlayableItem{container_type: :episode, container_id: episode_id}) do
    case Repo.one(
           from(e in Episode,
             join: s in Season,
             on: s.id == e.season_id,
             where: e.id == ^episode_id,
             select: s.tv_series_id
           )
         ) do
      nil -> {:orphan_episode, episode_id}
      tv_series_id -> {:tv_series, tv_series_id}
    end
  end

  defp entity_grouping_key(%PlayableItem{container_type: :movie, container_id: movie_id}) do
    case Repo.one(from(m in Movie, where: m.id == ^movie_id, select: m.movie_series_id)) do
      nil -> {:movie, movie_id}
      ms_id -> {:movie_series, ms_id}
    end
  end

  defp entity_grouping_key(%PlayableItem{container_type: type, container_id: id}), do: {type, id}

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
      images: list_images(:movie_series, movie_series_id),
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

  defp build_item_for_playable_item(
         %PlayableItem{container_type: type, container_id: cid} = item,
         shared
       ) do
    case fetch_container(type, cid) do
      nil ->
        nil

      container ->
        %DetailItem{
          playable_item_id: item.id,
          container_type: type,
          container_id: cid,
          name: leaf_name(type, item, container),
          position: item.position,
          duration_seconds: item.duration_seconds,
          date_published: leaf_date_published(type, container),
          description: leaf_description(type, container),
          parent_container_type: parent_container_type(type, container),
          parent_container_id: parent_container_id(type, container),
          parent_container_name: parent_container_name(type, container),
          container_name: container_name(type, container),
          container_description: container_description(type, container),
          container_year: container_year(type, container),
          container_url: container_url(type, container),
          container_tagline: container_tagline(type, container),
          container_genres: container_genres(type, container),
          container_studio: container_studio(type, container),
          container_country_code: container_country_code(type, container),
          container_original_language: container_original_language(type, container),
          container_network: container_network(type, container),
          container_status: container_status(type, container),
          container_duration_seconds: container_duration_seconds(type, container),
          container_content_rating: container_content_rating(type, container),
          container_aggregate_rating: container_aggregate_rating(type, container),
          container_vote_count: container_vote_count(type, container),
          container_number_of_seasons: container_number_of_seasons(type, container),
          container_director: container_director(type, container),
          cast: container_cast(type, container),
          crew: container_crew(type, container),
          extras: container_extras(type, container),
          external_ids: container_external_ids(type, container),
          imdb_id: external_id_value(container_external_ids(type, container), "imdb"),
          tmdb_id: external_id_value(container_external_ids(type, container), "tmdb"),
          present?: any_present_file?(item.id),
          images: shared.images,
          seasons: shared.seasons,
          movies: shared.movies,
          watched_files: list_watched_files_for_playable_item(item.id),
          subtitle_tracks: list_subtitle_tracks_for_playable_item(item.id)
        }
    end
  end

  defp rebuild_row(playable_item_id) do
    case build_item_for_playable_item_id(playable_item_id) do
      nil ->
        delete_row(playable_item_id)

      %DetailItem{} = item ->
        :ets.insert(@table, {playable_item_id, item})
        broadcast_row(playable_item_id)
    end
  end

  defp delete_row(playable_item_id) do
    :ets.delete(@table, playable_item_id)
    broadcast_row(playable_item_id)
  end

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

  defp broadcast_row(playable_item_id) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      Topics.library_views(),
      {:library_view_updated, :detail, playable_item_id}
    )
  end

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])

      _ref ->
        :ok
    end
  end

  # --- Container fetchers with preloads ---

  defp fetch_container(:movie, id) do
    Repo.one(
      from(m in Movie,
        where: m.id == ^id,
        preload: [:extras, :external_ids, movie_series: [:extras, :external_ids]]
      )
    )
  end

  defp fetch_container(:episode, id) do
    Repo.one(
      from(e in Episode,
        where: e.id == ^id,
        preload: [season: [tv_series: [:extras, :external_ids]]]
      )
    )
  end

  defp fetch_container(:video_object, id) do
    Repo.one(
      from(v in VideoObject,
        where: v.id == ^id,
        preload: [:external_ids]
      )
    )
  end

  defp fetch_container(_, _), do: nil

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

  defp container_name(type, container), do: Map.get(top_level_container(type, container), :name)

  defp container_description(type, container),
    do: Map.get(top_level_container(type, container), :description)

  defp container_year(type, container) do
    case top_level_container(type, container) do
      %{date_published: %Date{year: year}} -> year
      _ -> nil
    end
  end

  defp container_url(type, container), do: Map.get(top_level_container(type, container), :url)

  defp container_tagline(type, container), do: Map.get(top_level_container(type, container), :tagline)

  defp container_genres(type, container), do: Map.get(top_level_container(type, container), :genres)

  defp container_studio(type, container), do: Map.get(top_level_container(type, container), :studio)

  defp container_country_code(type, container),
    do: Map.get(top_level_container(type, container), :country_code)

  defp container_original_language(type, container),
    do: Map.get(top_level_container(type, container), :original_language)

  defp container_network(type, container), do: Map.get(top_level_container(type, container), :network)

  defp container_status(type, container), do: Map.get(top_level_container(type, container), :status)

  defp container_duration_seconds(type, container),
    do: Map.get(top_level_container(type, container), :duration_seconds)

  defp container_content_rating(type, container),
    do: Map.get(top_level_container(type, container), :content_rating)

  defp container_aggregate_rating(type, container),
    do: Map.get(top_level_container(type, container), :aggregate_rating_value)

  defp container_vote_count(type, container),
    do: Map.get(top_level_container(type, container), :vote_count)

  defp container_number_of_seasons(type, container),
    do: Map.get(top_level_container(type, container), :number_of_seasons)

  # Director is a per-Movie field, NOT a top-level metadata bubble-up.
  # For a multi-child MovieSeries the projection's container is a
  # constituent Movie; the entity-map for the MovieSeries modal must
  # not surface one child's director as the collection's director.
  defp container_director(:movie, %Movie{director: director}), do: director
  defp container_director(_type, _container), do: nil

  defp container_cast(type, container), do: Map.get(top_level_container(type, container), :cast)

  defp container_crew(type, container), do: Map.get(top_level_container(type, container), :crew)

  defp container_extras(type, container), do: Map.get(top_level_container(type, container), :extras)

  defp container_external_ids(type, container),
    do: Map.get(top_level_container(type, container), :external_ids)

  defp external_id_value(nil, _), do: nil

  defp external_id_value(external_ids, source) when is_list(external_ids) do
    Enum.find_value(external_ids, fn
      %{source: ^source, external_id: value} -> value
      _ -> nil
    end)
  end

  defp external_id_value(_, _), do: nil

  # --- Presence ---

  defp any_present_file?(playable_item_id) do
    query =
      from(w in WatchedFile,
        where: w.playable_item_id == ^playable_item_id,
        select: 1,
        limit: 1
      )

    Repo.one(query) == 1
  end

  # --- Phase 3.2: images / seasons / movies / watched_files / subtitles ---

  defp list_images(owner_type, owner_id) do
    Repo.all(
      from(i in Image,
        where: i.owner_type == ^owner_type and i.owner_id == ^owner_id
      )
    )
  end

  defp build_seasons_for_tv_series(tv_series_id) do
    # Load every Season under the series, plus its episodes and each
    # episode's PlayableItem id + presence flag. One query each for
    # seasons, episodes, presence — bounded, scales linearly with the
    # series.
    seasons =
      Repo.all(
        from(s in Season,
          where: s.tv_series_id == ^tv_series_id,
          order_by: [asc: s.season_number]
        )
      )

    if seasons == [] do
      []
    else
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

      pi_by_episode_id = Map.new(playable_items, fn pi -> {pi.container_id, pi} end)
      pi_ids = Enum.map(playable_items, & &1.id)

      watched_files_by_pi_id =
        if pi_ids == [] do
          %{}
        else
          Enum.group_by(
            Repo.all(
              from(w in WatchedFile,
                where: w.playable_item_id in ^pi_ids,
                order_by: [asc: w.inserted_at, asc: w.id]
              )
            ),
            & &1.playable_item_id
          )
        end

      extras_by_season_id =
        Enum.group_by(
          Repo.all(
            from(x in MediaCentarr.Library.Extra,
              where: x.owner_type == :season and x.owner_id in ^season_ids
            )
          ),
          & &1.owner_id
        )

      episode_images_by_episode_id =
        if episode_ids == [] do
          %{}
        else
          Enum.group_by(
            Repo.all(
              from(i in Image,
                where: i.owner_type == :episode and i.owner_id in ^episode_ids
              )
            ),
            & &1.owner_id
          )
        end

      episodes_by_season_id = Enum.group_by(episodes, & &1.season_id)

      Enum.map(seasons, fn season ->
        season_episodes =
          episodes_by_season_id
          |> Map.get(season.id, [])
          |> Enum.map(fn episode ->
            pi = Map.get(pi_by_episode_id, episode.id)
            files = (pi && Map.get(watched_files_by_pi_id, pi.id, [])) || []

            %DetailItem.Episode{
              episode_id: episode.id,
              playable_item_id: pi && pi.id,
              season_number: season.season_number,
              episode_number: episode.episode_number,
              name: episode.name,
              description: episode.description,
              date_published: nil,
              duration_seconds: episode.duration_seconds,
              present?: files != [],
              content_url: files |> List.first() |> file_path(),
              images: Map.get(episode_images_by_episode_id, episode.id, [])
            }
          end)

        %DetailItem.Season{
          season_number: season.season_number,
          name: season.name,
          number_of_episodes: season.number_of_episodes,
          episodes: season_episodes,
          extras: Map.get(extras_by_season_id, season.id, [])
        }
      end)
    end
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

      pi_by_movie_id = Map.new(playable_items, fn pi -> {pi.container_id, pi} end)
      pi_ids = Enum.map(playable_items, & &1.id)

      watched_files_by_pi_id =
        if pi_ids == [] do
          %{}
        else
          Enum.group_by(
            Repo.all(from(w in WatchedFile, where: w.playable_item_id in ^pi_ids)),
            & &1.playable_item_id
          )
        end

      Enum.map(movies, fn movie ->
        pi = Map.get(pi_by_movie_id, movie.id)
        files = (pi && Map.get(watched_files_by_pi_id, pi.id, [])) || []

        %DetailItem.MovieEntry{
          movie_id: movie.id,
          playable_item_id: pi && pi.id,
          name: movie.name,
          date_published: movie.date_published,
          collection_position: movie.position,
          content_url: files |> List.first() |> Map.get(:file_path),
          present?: files != []
        }
      end)
    end
  end

  defp list_watched_files_for_playable_item(playable_item_id) do
    Enum.map(
      Repo.all(
        from(w in WatchedFile,
          where: w.playable_item_id == ^playable_item_id,
          order_by: [asc: w.inserted_at, asc: w.id]
        )
      ),
      fn file ->
        %DetailItem.WatchedFile{
          path: file.file_path,
          watch_dir: file.watch_dir
        }
      end
    )
  end

  defp list_subtitle_tracks_for_playable_item(playable_item_id) do
    watched_file_ids =
      Repo.all(
        from(w in WatchedFile,
          where: w.playable_item_id == ^playable_item_id,
          select: w.id
        )
      )

    watched_file_ids
    |> Enum.flat_map(&Subtitles.list_tracks_for_file/1)
    |> Enum.map(fn track ->
      %DetailItem.SubtitleTrack{
        kind: track.kind,
        language: track.language,
        source: track.source
      }
    end)
  end
end
