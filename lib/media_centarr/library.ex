defmodule MediaCentarr.Library do
  use Boundary,
    deps: [MediaCentarr.Subtitles],
    exports: [
      Availability,
      Browser,
      EntityShape,
      Episode,
      EpisodeList,
      Events,
      Events.EntitiesChanged,
      ExtraFile,
      ExternalId,
      ExternalIds,
      FileEventHandler,
      Image,
      ImageHealth,
      Movie,
      MovieList,
      MovieSeries,
      Person,
      PlayableItem,
      ProgressSummary,
      Season,
      TVSeries,
      TypeResolver,
      VideoObject,
      Views,
      Views.ContinueWatching,
      Views.ContinueWatchingItem,
      Views.HeroCandidates,
      Views.HeroCandidatesItem,
      Views.RecentlyAdded,
      Views.RecentlyAddedItem,
      WatchedFile
    ]

  @moduledoc """
  The media library context — entities, images, external IDs, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  import Ecto.Query

  alias MediaCentarr.Repo

  alias MediaCentarr.Topics

  alias MediaCentarr.Library.{
    ChangeEntry,
    ContinueWatchingProgress,
    Episode,
    Extra,
    ExtraFile,
    ExtraProgress,
    ExternalId,
    ExternalIds,
    Image,
    Movie,
    MovieSeries,
    PlayableItem,
    PresentableQueries,
    Season,
    TVSeries,
    VideoObject,
    WatchProgress,
    WatchedFile
  }

  @doc "Subscribe the caller to library entity change events."
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, Topics.library_updates())
  end

  @tv_series_full_preloads [
    :images,
    :external_ids,
    :extras,
    :watched_files,
    seasons: [:extras, episodes: [:images, :watch_progress]]
  ]

  @movie_series_full_preloads [
    :images,
    :external_ids,
    :extras,
    :watched_files,
    movies: [:images, :watch_progress]
  ]

  @movie_full_preloads [
    :images,
    :external_ids,
    :extras,
    :watched_files,
    :watch_progress
  ]

  @video_object_full_preloads [
    :images,
    :external_ids,
    :watched_files,
    :watch_progress
  ]

  @doc """
  Returns a `[type: preloads]` keyword list covering the four playable entity
  types. Used by `TypeResolver.resolve/2` and other multi-type lookups that
  preload across all four tables in one call.
  """
  def full_preloads_by_type do
    [
      tv_series: @tv_series_full_preloads,
      movie_series: @movie_series_full_preloads,
      movie: @movie_full_preloads,
      video_object: @video_object_full_preloads
    ]
  end

  # ---------------------------------------------------------------------------
  # TVSeries
  # ---------------------------------------------------------------------------

  def fetch_tv_series(id) do
    case Repo.get(TVSeries, id) do
      nil -> {:error, :not_found}
      tv_series -> {:ok, tv_series}
    end
  end

  def get_tv_series!(id), do: Repo.get!(TVSeries, id)

  def fetch_tv_series_with_associations(id) do
    case Repo.get(TVSeries, id) do
      nil -> {:error, :not_found}
      tv_series -> {:ok, Repo.preload(tv_series, @tv_series_full_preloads)}
    end
  end

  def get_tv_series_with_associations!(id) do
    Repo.preload(Repo.get!(TVSeries, id), @tv_series_full_preloads)
  end

  def create_tv_series(attrs) do
    Repo.insert(TVSeries.create_changeset(attrs))
  end

  def create_tv_series!(attrs), do: Repo.bang!(create_tv_series(attrs))

  def update_tv_series(tv_series, attrs) do
    Repo.update(TVSeries.update_changeset(tv_series, attrs))
  end

  def update_tv_series!(tv_series, attrs), do: Repo.bang!(update_tv_series(tv_series, attrs))

  def destroy_tv_series(tv_series), do: Repo.delete(tv_series)
  def destroy_tv_series!(tv_series), do: destroy_bang!(tv_series)

  # ---------------------------------------------------------------------------
  # MovieSeries
  # ---------------------------------------------------------------------------

  def fetch_movie_series(id) do
    case Repo.get(MovieSeries, id) do
      nil -> {:error, :not_found}
      movie_series -> {:ok, movie_series}
    end
  end

  def get_movie_series!(id), do: Repo.get!(MovieSeries, id)

  def fetch_movie_series_with_associations(id) do
    case Repo.get(MovieSeries, id) do
      nil -> {:error, :not_found}
      movie_series -> {:ok, Repo.preload(movie_series, @movie_series_full_preloads)}
    end
  end

  def get_movie_series_with_associations!(id) do
    Repo.preload(Repo.get!(MovieSeries, id), @movie_series_full_preloads)
  end

  def create_movie_series(attrs) do
    Repo.insert(MovieSeries.create_changeset(attrs))
  end

  def create_movie_series!(attrs), do: Repo.bang!(create_movie_series(attrs))

  def update_movie_series(movie_series, attrs) do
    Repo.update(MovieSeries.update_changeset(movie_series, attrs))
  end

  def update_movie_series!(movie_series, attrs), do: Repo.bang!(update_movie_series(movie_series, attrs))

  def destroy_movie_series(movie_series), do: Repo.delete(movie_series)
  def destroy_movie_series!(movie_series), do: destroy_bang!(movie_series)

  # ---------------------------------------------------------------------------
  # VideoObject
  # ---------------------------------------------------------------------------

  def fetch_video_object(id) do
    case Repo.get(VideoObject, id) do
      nil -> {:error, :not_found}
      video_object -> {:ok, video_object}
    end
  end

  def get_video_object!(id), do: Repo.get!(VideoObject, id)

  def fetch_video_object_with_associations(id) do
    case Repo.get(VideoObject, id) do
      nil -> {:error, :not_found}
      video_object -> {:ok, Repo.preload(video_object, @video_object_full_preloads)}
    end
  end

  def get_video_object_with_associations!(id) do
    Repo.preload(Repo.get!(VideoObject, id), @video_object_full_preloads)
  end

  def create_video_object(attrs) do
    Repo.insert(VideoObject.create_changeset(attrs))
  end

  def create_video_object!(attrs), do: Repo.bang!(create_video_object(attrs))

  def update_video_object(video_object, attrs) do
    Repo.update(VideoObject.update_changeset(video_object, attrs))
  end

  def update_video_object!(video_object, attrs), do: Repo.bang!(update_video_object(video_object, attrs))

  def destroy_video_object(video_object), do: Repo.delete(video_object)
  def destroy_video_object!(video_object), do: destroy_bang!(video_object)

  # ---------------------------------------------------------------------------
  # PlayableItem
  # ---------------------------------------------------------------------------

  @doc """
  Inserts a new `PlayableItem` row. The caller is responsible for ensuring
  the `(container_type, container_id)` pair points at an existing container
  — there is no DB-level FK enforcement (see `PlayableItem` moduledoc for
  the discriminator design decision).
  """
  @spec create_playable_item(map()) :: {:ok, PlayableItem.t()} | {:error, Ecto.Changeset.t()}
  def create_playable_item(attrs) do
    Repo.insert(PlayableItem.create_changeset(attrs))
  end

  @doc "Bang variant of `create_playable_item/1` — raises on changeset error."
  @spec create_playable_item!(map()) :: PlayableItem.t()
  def create_playable_item!(attrs), do: Repo.bang!(create_playable_item(attrs))

  @doc """
  Fetches a `PlayableItem` by id. Returns `{:ok, item}` or `{:error, :not_found}`.
  """
  @spec fetch_playable_item(Ecto.UUID.t()) :: {:ok, PlayableItem.t()} | {:error, :not_found}
  def fetch_playable_item(id) do
    case Repo.get(PlayableItem, id) do
      nil -> {:error, :not_found}
      item -> {:ok, item}
    end
  end

  @doc """
  Lists all `PlayableItem` rows for a given container, ordered by `:position`
  ascending. Returns an empty list when no items exist for the container.
  """
  @spec list_playable_items_for(PlayableItem.container_type(), Ecto.UUID.t()) :: [PlayableItem.t()]
  def list_playable_items_for(container_type, container_id)
      when container_type in [:movie, :episode, :video_object] and is_binary(container_id) do
    Repo.all(
      from(p in PlayableItem,
        where: p.container_type == ^container_type and p.container_id == ^container_id,
        order_by: [asc: p.position]
      )
    )
  end

  @doc """
  Fetches the `PlayableItem` row at the exact `(container_type, container_id,
  position)` triple. Used by `Library.Inbound` for race-loss recovery on the
  uniqueness constraint — the recovery semantically wants the row at the
  SAME position, not just any row for the container (a container can carry
  multiple PlayableItems for director's cuts).

  Returns `nil` if no row exists for the triple.
  """
  @spec find_playable_item(PlayableItem.container_type(), Ecto.UUID.t(), integer()) ::
          PlayableItem.t() | nil
  def find_playable_item(container_type, container_id, position)
      when container_type in [:movie, :episode, :video_object] and is_binary(container_id) and
             is_integer(position) do
    Repo.one(
      from(p in PlayableItem,
        where:
          p.container_type == ^container_type and p.container_id == ^container_id and
            p.position == ^position
      )
    )
  end

  @doc """
  Finds the `PlayableItem` at `(container_type, container_id, position)`,
  creating it if absent. Race-loss recovery follows the same pattern as
  `Library.Inbound.ensure_playable_item_for_event/2`: a concurrent insert
  surfaces as a `unique_constraint` changeset error and we re-fetch the
  winning row.

  Returns `{:ok, item}` or `{:error, reason}`. Used by the WatchProgress
  writer seam (`find_or_create_watch_progress_for_*`) so a save against a
  not-yet-ingested leaf does not race with `Library.Inbound`.
  """
  @spec find_or_create_playable_item(
          PlayableItem.container_type(),
          Ecto.UUID.t(),
          integer()
        ) :: {:ok, PlayableItem.t()} | {:error, term()}
  def find_or_create_playable_item(container_type, container_id, position)
      when container_type in [:movie, :episode, :video_object] and is_binary(container_id) and
             is_integer(position) do
    case find_playable_item(container_type, container_id, position) do
      %PlayableItem{} = item ->
        {:ok, item}

      nil ->
        case create_playable_item(%{
               container_type: container_type,
               container_id: container_id,
               position: position
             }) do
          {:ok, item} ->
            {:ok, item}

          {:error, %Ecto.Changeset{errors: errors}} ->
            if Keyword.has_key?(errors, :container_type) or
                 Keyword.has_key?(errors, :container_id) or
                 Keyword.has_key?(errors, :position) do
              case find_playable_item(container_type, container_id, position) do
                %PlayableItem{} = item -> {:ok, item}
                nil -> {:error, :race_loss_recovery_failed}
              end
            else
              {:error, errors}
            end
        end
    end
  end

  @doc "Deletes a `PlayableItem` row."
  @spec destroy_playable_item(PlayableItem.t()) :: {:ok, PlayableItem.t()} | {:error, Ecto.Changeset.t()}
  def destroy_playable_item(item), do: Repo.delete(item)

  @doc "Bang variant of `destroy_playable_item/1`."
  @spec destroy_playable_item!(PlayableItem.t()) :: :ok
  def destroy_playable_item!(item), do: destroy_bang!(item)

  # ---------------------------------------------------------------------------
  # WatchedFile
  # ---------------------------------------------------------------------------

  def list_watched_files, do: Repo.all(WatchedFile)

  def link_file(attrs) do
    file_path = attrs[:file_path] || attrs["file_path"]

    case Repo.get_by(WatchedFile, file_path: file_path) do
      nil -> Repo.insert(WatchedFile.link_file_changeset(attrs))
      existing -> Repo.update(WatchedFile.link_file_changeset(existing, attrs))
    end
  end

  def link_file!(attrs), do: Repo.bang!(link_file(attrs))

  def list_files_by_paths(file_paths) do
    Repo.all(from(w in WatchedFile, where: w.file_path in ^file_paths))
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

  def list_files_by_watch_dir(watch_dir) do
    Repo.all(from(w in WatchedFile, where: w.watch_dir == ^watch_dir))
  end

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

    from(m in Movie, where: m.movie_series_id == ^owner_id)
    |> Repo.all()
    |> maybe_preload(preloads)
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
  Loads a single library entry shaped for the detail modal. Returns the same
  `%{entity, progress, progress_records}` map `Library.Browser` produces for
  the catalog grid, but for one ID and with extras already populated.

  Returns `:not_found` when no entity matches the ID *and* has at least one
  present file (the same gating `Browser.fetch_typed_entries_by_ids/1`
  applies — orphan entities don't appear in the modal).
  """
  @spec load_modal_entry(Ecto.UUID.t()) ::
          {:ok, %{entity: map(), progress: map(), progress_records: list()}}
          | :not_found
  def load_modal_entry(id) when is_binary(id) do
    case __MODULE__.Browser.fetch_typed_entries_by_ids([id]) do
      {[entry], _gone} ->
        {:ok, %{entry | entity: load_extras_for_entity(entry.entity)}}

      {[], _gone} ->
        :not_found
    end
  end

  @doc """
  Populates `extras` on a normalized entity map (and `extras` on each season for
  TV series) without reloading the full entity. Issues at most two queries.

  Called on-demand when the detail panel opens for a selected entity, so the
  catalog grid load stays free of extras queries.
  """
  def load_extras_for_entity(%{id: owner_id, type: :tv_series, seasons: seasons} = entity) do
    season_ids = Enum.map(seasons, & &1.id)

    all_extras =
      Repo.all(
        from(x in Extra,
          where:
            (x.owner_type == :tv_series and x.owner_id == ^owner_id) or
              (x.owner_type == :season and x.owner_id in ^season_ids)
        )
      )

    {entity_extras, season_extras_by_id} = split_extras_by_owner(all_extras)

    seasons_with_extras =
      Enum.map(seasons, fn season ->
        %{season | extras: Map.get(season_extras_by_id, season.id, [])}
      end)

    %{entity | extras: entity_extras, seasons: seasons_with_extras}
  end

  def load_extras_for_entity(%{id: owner_id} = entity) do
    entity_extras = list_extras_by_owner_id(owner_id)
    %{entity | extras: entity_extras}
  end

  defp split_extras_by_owner(extras) do
    {season_extras, entity_extras} = Enum.split_with(extras, &(&1.owner_type == :season))
    season_extras_by_id = Enum.group_by(season_extras, & &1.owner_id)
    {entity_extras, season_extras_by_id}
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
    Repo.insert(Image.create_changeset(translate_image_owner(attrs)),
      on_conflict: {:replace, [:content_url, :extension, :updated_at]},
      conflict_target: conflict_target
    )
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

  def update_image(image, attrs) do
    Repo.update(Image.update_changeset(image, attrs))
  end

  def update_image!(image, attrs), do: Repo.bang!(update_image(image, attrs))

  def destroy_image(image), do: Repo.delete(image)
  def destroy_image!(image), do: destroy_bang!(image)

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
      {entity_id, "/media-images/#{content_url}"}
    end)
  end

  # ---------------------------------------------------------------------------
  # ExternalId
  # ---------------------------------------------------------------------------

  def find_or_create_external_id(attrs) do
    translated = translate_external_id_owner(Map.new(attrs))

    find_or_insert_by(
      ExternalId,
      [source: lookup_attr(translated, :source), external_id: lookup_attr(translated, :external_id)],
      translated
    )
  end

  def find_or_create_external_id!(attrs), do: Repo.bang!(find_or_create_external_id(attrs))

  def create_external_id(attrs) do
    Repo.insert(ExternalId.create_changeset(translate_external_id_owner(attrs)))
  end

  def create_external_id!(attrs), do: Repo.bang!(create_external_id(attrs))

  def destroy_external_id(external_id), do: Repo.delete(external_id)
  def destroy_external_id!(external_id), do: destroy_bang!(external_id)

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
  @spec find_by_external_id(MediaCentarr.Library.ExternalIds.owner_type(), String.t()) ::
          MediaCentarr.Library.ExternalIds.owner() | nil
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
  Returns `{:ok, content_url}` if the library has a movie with this
  TMDB id whose file has been ingested (`content_url` is set), otherwise
  `:not_found`. Used by `Acquisition.Pursuits.LibraryReconciler` as the
  safety-net check against the PubSub-driven completion path.
  """
  @spec find_present_movie(String.t()) :: {:ok, String.t()} | :not_found
  def find_present_movie(tmdb_id) when is_binary(tmdb_id) do
    case Repo.one(
           from(m in Movie,
             join: e in ExternalId,
             on: e.owner_id == m.id and e.owner_type == :movie,
             where: e.source == "tmdb" and e.external_id == ^tmdb_id and not is_nil(m.content_url),
             select: m.content_url,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
  end

  @doc """
  Returns `{:ok, content_url}` if the library has an episode for the
  given `(tmdb_id, season_number, episode_number)` tuple whose file has
  been ingested, otherwise `:not_found`. Joins through TVSeries → Season
  → Episode in a single query, using `library_external_ids` to resolve
  the TMDB id onto the series.
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
             where:
               ext.source == "tmdb" and ext.external_id == ^tmdb_id and
                 s.season_number == ^season_number and
                 e.episode_number == ^episode_number and not is_nil(e.content_url),
             select: e.content_url,
             limit: 1
           )
         ) do
      nil -> :not_found
      url -> {:ok, url}
    end
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
  # Movie
  # ---------------------------------------------------------------------------

  def list_movies, do: Repo.all(Movie)

  def fetch_movie(id) do
    case Repo.get(Movie, id) do
      nil -> {:error, :not_found}
      movie -> {:ok, movie}
    end
  end

  def get_movie!(id), do: Repo.get!(Movie, id)

  def set_movie_content_url(movie, attrs) do
    Repo.update(Movie.set_content_url_changeset(movie, attrs))
  end

  def set_movie_content_url!(movie, attrs), do: Repo.bang!(set_movie_content_url(movie, attrs))

  def create_movie(attrs) do
    Repo.insert(Movie.create_changeset(attrs))
  end

  def create_movie!(attrs), do: Repo.bang!(create_movie(attrs))

  def destroy_movie(movie), do: Repo.delete(movie)
  def destroy_movie!(movie), do: destroy_bang!(movie)

  def fetch_movie_with_associations(id) do
    case Repo.get(Movie, id) do
      nil -> {:error, :not_found}
      movie -> {:ok, Repo.preload(movie, @movie_full_preloads)}
    end
  end

  def get_movie_with_associations!(id) do
    Repo.preload(Repo.get!(Movie, id), @movie_full_preloads)
  end

  @doc """
  Finds the child movie of a `MovieSeries` whose TMDB ExternalId matches
  the supplied `:tmdb_id`, or creates one. The TMDB id is written as a
  separate ExternalId row on success — the Movie row itself no longer
  carries the id column.

  Used by `Library.Inbound` when ingesting a collection event with a
  child-movie payload.
  """
  def find_or_create_movie_for_series(attrs) do
    movie_series_id = lookup_attr(attrs, :movie_series_id)
    tmdb_id = lookup_attr(attrs, :tmdb_id)

    case find_child_movie_by_tmdb_id(movie_series_id, tmdb_id) do
      %Movie{} = movie ->
        {:ok, movie}

      nil ->
        attrs_without_id = Map.drop(attrs, [:tmdb_id, "tmdb_id"])

        with {:ok, movie} <- create_movie(attrs_without_id),
             {:ok, _} <- maybe_put_tmdb(movie, tmdb_id) do
          {:ok, movie}
        end
    end
  end

  defp find_child_movie_by_tmdb_id(_movie_series_id, nil), do: nil

  defp find_child_movie_by_tmdb_id(movie_series_id, tmdb_id)
       when is_binary(movie_series_id) and is_binary(tmdb_id) do
    Repo.one(
      from(m in Movie,
        join: e in ExternalId,
        on: e.owner_id == m.id and e.owner_type == :movie,
        where:
          m.movie_series_id == ^movie_series_id and
            e.source == "tmdb" and e.external_id == ^tmdb_id,
        limit: 1
      )
    )
  end

  defp maybe_put_tmdb(_movie, nil), do: {:ok, :no_id}

  defp maybe_put_tmdb(movie, tmdb_id) when is_binary(tmdb_id) do
    ExternalIds.put(:tmdb, movie, tmdb_id)
  end

  def list_movies_for_series(movie_series_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    from(m in Movie, where: m.movie_series_id == ^movie_series_id)
    |> Repo.all()
    |> maybe_preload(preloads)
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

  def get_extra!(id), do: Repo.get!(Extra, id)

  @doc """
  Find or create an extra by its `(owner_type, owner_id, content_url)`
  tuple. Used by ingest to upsert extras without re-discovering the
  same bonus feature on every Watcher event.
  """
  def find_or_create_extra_by_owner(attrs) do
    find_or_insert_by(
      Extra,
      [
        owner_type: lookup_attr(attrs, :owner_type),
        owner_id: lookup_attr(attrs, :owner_id),
        content_url: lookup_attr(attrs, :content_url)
      ],
      attrs
    )
  end

  def create_extra(attrs) do
    Repo.insert(Extra.create_changeset(translate_extra_owner(attrs)))
  end

  def create_extra!(attrs), do: Repo.bang!(create_extra(attrs))

  def destroy_extra(extra), do: Repo.delete(extra)
  def destroy_extra!(extra), do: destroy_bang!(extra)

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
    file_path = lookup_attr(attrs, :file_path)

    case Repo.get_by(ExtraFile, file_path: file_path) do
      nil -> Repo.insert(ExtraFile.link_file_changeset(attrs))
      existing -> Repo.update(ExtraFile.link_file_changeset(existing, attrs))
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

  def get_season!(id), do: Repo.get!(Season, id)

  def create_season(attrs) do
    Repo.insert(Season.create_changeset(attrs))
  end

  def create_season!(attrs), do: Repo.bang!(create_season(attrs))

  def destroy_season(season), do: Repo.delete(season)
  def destroy_season!(season), do: destroy_bang!(season)

  def find_or_create_season_for_tv_series(attrs) do
    find_or_insert_by(
      Season,
      [
        tv_series_id: lookup_attr(attrs, :tv_series_id),
        season_number: lookup_attr(attrs, :season_number)
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

    from(e in Episode, where: e.season_id == ^season_id)
    |> Repo.all()
    |> maybe_preload(preloads)
  end

  def fetch_episode(id) do
    case Repo.get(Episode, id) do
      nil -> {:error, :not_found}
      episode -> {:ok, episode}
    end
  end

  def get_episode!(id), do: Repo.get!(Episode, id)

  def find_or_create_episode(attrs) do
    find_or_insert_by(
      Episode,
      [season_id: lookup_attr(attrs, :season_id), episode_number: lookup_attr(attrs, :episode_number)],
      attrs
    )
  end

  def find_or_create_episode!(attrs), do: Repo.bang!(find_or_create_episode(attrs))

  @doc """
  Finds the Episode under `tv_series_id` whose `content_url` matches
  `file_path`. Used by `Library.Inbound` to resolve the leaf Episode
  for an incoming TV WatchedFile (Library Schema v2 Phase 2 Task B).

  Returns `nil` when no Episode matches — callers must handle the
  missing-row case (typically an ingest race or a stale event).
  """
  @spec find_episode_by_content_url(Ecto.UUID.t(), String.t()) :: Episode.t() | nil
  def find_episode_by_content_url(tv_series_id, file_path)
      when is_binary(tv_series_id) and is_binary(file_path) do
    Repo.one(
      from(e in Episode,
        join: s in Season,
        on: s.id == e.season_id,
        where: s.tv_series_id == ^tv_series_id and e.content_url == ^file_path,
        limit: 1
      )
    )
  end

  @doc """
  Finds the child Movie under `movie_series_id` whose `content_url`
  matches `file_path`. The collection-child counterpart of
  `find_episode_by_content_url/2`.
  """
  @spec find_movie_by_content_url(Ecto.UUID.t(), String.t()) :: Movie.t() | nil
  def find_movie_by_content_url(movie_series_id, file_path)
      when is_binary(movie_series_id) and is_binary(file_path) do
    Repo.one(
      from(m in Movie,
        where: m.movie_series_id == ^movie_series_id and m.content_url == ^file_path,
        limit: 1
      )
    )
  end

  def set_episode_content_url(episode, attrs) do
    Repo.update(Episode.set_content_url_changeset(episode, attrs))
  end

  def set_episode_content_url!(episode, attrs) do
    Repo.bang!(set_episode_content_url(episode, attrs))
  end

  def create_episode(attrs) do
    Repo.insert(Episode.create_changeset(attrs))
  end

  def create_episode!(attrs), do: Repo.bang!(create_episode(attrs))

  def destroy_episode(episode), do: Repo.delete(episode)
  def destroy_episode!(episode), do: destroy_bang!(episode)

  # ---------------------------------------------------------------------------
  # WatchProgress
  # ---------------------------------------------------------------------------

  def list_watch_progress, do: Repo.all(WatchProgress)

  def mark_watch_completed(progress) do
    transitioning? = not progress.completed

    with {:ok, updated} <- Repo.update(WatchProgress.mark_completed_changeset(progress)) do
      if transitioning? do
        Phoenix.PubSub.broadcast(
          MediaCentarr.PubSub,
          MediaCentarr.Topics.library_watch_completed(),
          {:entity_watch_completed, updated}
        )
      end

      {:ok, updated}
    end
  end

  def mark_watch_completed!(progress), do: Repo.bang!(mark_watch_completed(progress))

  def mark_watch_incomplete(progress) do
    Repo.update(WatchProgress.mark_incomplete_changeset(progress))
  end

  def mark_watch_incomplete!(progress), do: Repo.bang!(mark_watch_incomplete(progress))

  def destroy_watch_progress(progress), do: Repo.delete(progress)
  def destroy_watch_progress!(progress), do: destroy_bang!(progress)

  @doc """
  Fetches a watch progress record by the legacy FK key/value pair, resolving
  through PlayableItem. The `fk_key` is one of `:movie_id`, `:episode_id`,
  `:video_object_id` and identifies the container; the FK on
  `library_watch_progress` itself is now `:playable_item_id`
  (Library Schema v2 Phase 2 Task C).

  The function is kept for callers that still think in container-FK terms
  (`MediaCentarr.WatchHistory.reset_watch_progress/1`,
  `EntityModal.update_watch_progress/3`). New code should preload through
  `playable_items` and read `entity.watch_progress` directly.
  """
  @spec fetch_watch_progress_by_fk(:movie_id | :episode_id | :video_object_id, Ecto.UUID.t()) ::
          {:ok, WatchProgress.t()} | {:error, :not_found}
  def fetch_watch_progress_by_fk(:movie_id, id), do: fetch_progress_for_container(:movie, id)
  def fetch_watch_progress_by_fk(:episode_id, id), do: fetch_progress_for_container(:episode, id)

  def fetch_watch_progress_by_fk(:video_object_id, id),
    do: fetch_progress_for_container(:video_object, id)

  defp fetch_progress_for_container(container_type, container_id) do
    query =
      from(wp in WatchProgress,
        join: pi in PlayableItem,
        on: pi.id == wp.playable_item_id,
        where: pi.container_type == ^container_type and pi.container_id == ^container_id,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  @doc """
  Upserts a WatchProgress row for the given Movie. `attrs` may carry the legacy
  `:movie_id` key (the canonical caller form) — internally the function
  resolves the canonical PlayableItem `(:movie, movie_id, position: 1)` (or
  the movie's `position`) and writes `:playable_item_id`.
  """
  def find_or_create_watch_progress_for_movie(attrs) do
    movie_id = lookup_attr(attrs, :movie_id)

    position =
      case Repo.get(Movie, movie_id) do
        %Movie{position: pos} when is_integer(pos) -> pos
        _ -> 1
      end

    find_or_create_watch_progress_for_container(:movie, movie_id, position, attrs)
  end

  @doc """
  Upserts a WatchProgress row for the given Episode. `attrs` may carry the
  legacy `:episode_id` key — internally we resolve the PlayableItem at
  `(:episode, episode_id, position: episode.episode_number)` to match the
  Task B convention.
  """
  def find_or_create_watch_progress_for_episode(attrs) do
    episode_id = lookup_attr(attrs, :episode_id)

    position =
      case Repo.get(Episode, episode_id) do
        %Episode{episode_number: n} when is_integer(n) -> n
        _ -> 1
      end

    find_or_create_watch_progress_for_container(:episode, episode_id, position, attrs)
  end

  @doc """
  Upserts a WatchProgress row for the given VideoObject. Canonical position
  is 1 (VideoObjects don't carry multi-cut variants in current schema).
  """
  def find_or_create_watch_progress_for_video_object(attrs) do
    vo_id = lookup_attr(attrs, :video_object_id)
    find_or_create_watch_progress_for_container(:video_object, vo_id, 1, attrs)
  end

  defp find_or_create_watch_progress_for_container(container_type, container_id, position, attrs) do
    with {:ok, playable_item} <-
           find_or_create_playable_item(container_type, container_id, position) do
      cleaned_attrs =
        attrs
        |> Map.new()
        |> Map.drop([:movie_id, :episode_id, :video_object_id])
        |> Map.put(:playable_item_id, playable_item.id)

      upsert_by(WatchProgress, [playable_item_id: playable_item.id], cleaned_attrs)
    end
  end

  # ---------------------------------------------------------------------------
  # ExtraProgress
  # ---------------------------------------------------------------------------

  def get_extra_progress_by_extra(extra_id) do
    Repo.get_by(ExtraProgress, extra_id: extra_id)
  end

  def find_or_create_extra_progress(attrs) do
    upsert_by(ExtraProgress, [extra_id: lookup_attr(attrs, :extra_id)], attrs)
  end

  def find_or_create_extra_progress!(attrs), do: Repo.bang!(find_or_create_extra_progress(attrs))

  def mark_extra_completed(progress) do
    Repo.update(ExtraProgress.mark_completed_changeset(progress))
  end

  def mark_extra_completed!(progress), do: Repo.bang!(mark_extra_completed(progress))

  def mark_extra_incomplete(progress) do
    Repo.update(ExtraProgress.mark_incomplete_changeset(progress))
  end

  def mark_extra_incomplete!(progress), do: Repo.bang!(mark_extra_incomplete(progress))

  def destroy_extra_progress(progress), do: Repo.delete(progress)
  def destroy_extra_progress!(progress), do: destroy_bang!(progress)

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
  defdelegate broadcast_entities_changed(entity_ids), to: MediaCentarr.Library.Helpers

  # ---------------------------------------------------------------------------
  # HomeLive Facade
  # ---------------------------------------------------------------------------

  @epoch_datetime ~U[1970-01-01 00:00:00Z]

  @doc """
  List in-progress titles (those with watch progress that is not yet completed),
  most recently watched first. Used by HomeLive's Continue Watching row.

  Returns a list of plain maps in the shape:
    `%{entity_id, entity_name, last_episode_label, progress_pct, backdrop_url}`

  `progress_pct` is 0..100 (integer).

  Includes entities whose underlying file is not currently present in any
  watch_dir — Continue Watching is the user's mental list of "things I'm
  watching", and an absent file does not erase that. Playback handles the
  missing-file case at the action layer.

  Issues at most ~15 targeted queries regardless of library size, compared to
  the ~87 queries of the previous `fetch_all_typed_entries` approach.
  """
  @spec list_in_progress(keyword()) :: [map()]
  def list_in_progress(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    movie_entries = fetch_in_progress_movies(limit)
    hoisted_entries = fetch_in_progress_hoisted_movies(limit)
    tv_series_entries = fetch_in_progress_tv_series(limit)
    video_object_entries = fetch_in_progress_video_objects(limit)
    movie_series_entries = fetch_in_progress_movie_series(limit)

    (movie_entries ++
       hoisted_entries ++ tv_series_entries ++ video_object_entries ++ movie_series_entries)
    |> Enum.sort_by(
      fn entry -> entry_last_watched_at(entry) || @epoch_datetime end,
      {:desc, DateTime}
    )
    |> Enum.take(limit)
    |> Enum.map(&shape_in_progress_row/1)
  end

  @doc """
  List recently-added entities (newest `inserted_at` first), regardless of
  entity type. Returns plain maps in the shape:
    `%{id, name, year, poster_url}`

  Issues at most 8 queries: one per entity type + one image preload per type,
  compared to ~87 queries for the previous `fetch_all_typed_entries` approach.
  """
  @spec list_recently_added(keyword()) :: [map()]
  def list_recently_added(opts \\ []) do
    limit = Keyword.get(opts, :limit, 16)

    movies = fetch_recently_added_movies(limit)
    hoisted = fetch_recently_added_hoisted_movies(limit)
    tv_series = fetch_recently_added_tv_series(limit)
    movie_series = fetch_recently_added_movie_series(limit)
    video_objects = fetch_recently_added_video_objects(limit)

    (movies ++ hoisted ++ tv_series ++ movie_series ++ video_objects)
    |> Enum.sort_by(& &1.__inserted_at__, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :__inserted_at__))
  end

  defp fetch_recently_added_movies(limit) do
    from([m] in PresentableQueries.standalone_movies(),
      order_by: [{:desc, m.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  defp fetch_recently_added_hoisted_movies(limit) do
    from([m] in PresentableQueries.singleton_collection_movies(),
      order_by: [{:desc, m.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  defp fetch_recently_added_tv_series(limit) do
    from(t in TVSeries,
      as: :item,
      where: exists(tv_series_present_file_subquery()),
      order_by: [{:desc, t.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  # WatchedFile present for any episode in any season of `parent_as(:item)`
  # (a TVSeries). Walks `WatchedFile → PlayableItem(:episode) → Episode →
  # Season → TVSeries`. Used by recently-added and hero-candidates surfaces.
  defp tv_series_present_file_subquery do
    from(wf in WatchedFile,
      join: kf in "watcher_files",
      on: kf.file_path == wf.file_path,
      join: pi in PlayableItem,
      on: pi.id == wf.playable_item_id and pi.container_type == :episode,
      join: e in Episode,
      on: e.id == pi.container_id,
      join: s in Season,
      on: s.id == e.season_id,
      where: s.tv_series_id == parent_as(:item).id and kf.state == "present",
      select: 1
    )
  end

  # WatchedFile present for the VideoObject in `parent_as(:item)`.
  defp video_object_present_file_subquery do
    from(wf in WatchedFile,
      join: kf in "watcher_files",
      on: kf.file_path == wf.file_path,
      join: pi in PlayableItem,
      on: pi.id == wf.playable_item_id and pi.container_type == :video_object,
      where: pi.container_id == parent_as(:item).id and kf.state == "present",
      select: 1
    )
  end

  defp fetch_recently_added_movie_series(limit) do
    from([ms] in PresentableQueries.multi_child_movie_series(),
      order_by: [{:desc, ms.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  defp fetch_recently_added_video_objects(limit) do
    from(v in VideoObject,
      as: :item,
      where: exists(video_object_present_file_subquery()),
      order_by: [{:desc, v.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  @doc """
  List entities suitable as Home page hero (those with both a backdrop
  image and a description). Returns plain maps in the shape:
    `%{id, name, year, runtime_minutes, genres, overview, backdrop_url}`

  Issues at most 8 queries: one per entity type + one image preload per type,
  compared to ~87 queries for the previous `fetch_all_typed_entries` approach.
  """
  @spec list_hero_candidates(keyword()) :: [map()]
  def list_hero_candidates(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    movies = fetch_hero_candidates_movies(limit)
    hoisted = fetch_hero_candidates_hoisted_movies(limit)
    tv_series = fetch_hero_candidates_tv_series(limit)
    movie_series = fetch_hero_candidates_movie_series(limit)
    video_objects = fetch_hero_candidates_video_objects(limit)

    Enum.take(movies ++ hoisted ++ tv_series ++ movie_series ++ video_objects, limit)
  end

  # --- Private fetchers for list_hero_candidates ---

  defp fetch_hero_candidates_movies(limit) do
    from([m] in PresentableQueries.standalone_movies(),
      where:
        not is_nil(m.description) and
          fragment("TRIM(?)", m.description) != "" and
          exists(
            from(img in Image,
              where:
                img.owner_id == parent_as(:item).id and img.owner_type == :movie and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ),
      order_by: [{:desc, m.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_hero_record/1)
  end

  # Hoists singleton-collection movies (the sole present child of their MovieSeries)
  # so a 1-child collection container is replaced by the child movie itself.
  defp fetch_hero_candidates_hoisted_movies(limit) do
    from([m] in PresentableQueries.singleton_collection_movies(),
      where:
        not is_nil(m.description) and
          fragment("TRIM(?)", m.description) != "" and
          exists(
            from(img in Image,
              where:
                img.owner_id == parent_as(:item).id and img.owner_type == :movie and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ),
      order_by: [{:desc, m.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_hero_record/1)
  end

  defp fetch_hero_candidates_tv_series(limit) do
    from(t in TVSeries,
      as: :entity,
      where:
        not is_nil(t.description) and
          fragment("TRIM(?)", t.description) != "" and
          exists(
            from(img in Image,
              where:
                img.owner_id == parent_as(:entity).id and img.owner_type == :tv_series and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ) and
          exists(
            from(wf in WatchedFile,
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              join: pi in PlayableItem,
              on: pi.id == wf.playable_item_id and pi.container_type == :episode,
              join: e in Episode,
              on: e.id == pi.container_id,
              join: s in Season,
              on: s.id == e.season_id,
              where: s.tv_series_id == parent_as(:entity).id and kf.state == "present",
              select: 1
            )
          ),
      order_by: [{:desc, t.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_hero_record/1)
  end

  defp fetch_hero_candidates_movie_series(limit) do
    from([ms] in PresentableQueries.multi_child_movie_series(),
      where:
        not is_nil(ms.description) and
          fragment("TRIM(?)", ms.description) != "" and
          exists(
            from(img in Image,
              where:
                img.owner_id == parent_as(:item).id and img.owner_type == :movie_series and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ),
      order_by: [{:desc, ms.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_hero_record/1)
  end

  defp fetch_hero_candidates_video_objects(limit) do
    from(v in VideoObject,
      as: :entity,
      where:
        not is_nil(v.description) and
          fragment("TRIM(?)", v.description) != "" and
          exists(
            from(img in Image,
              where:
                img.owner_id == parent_as(:entity).id and img.owner_type == :video_object and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ) and
          exists(
            from(wf in WatchedFile,
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              join: pi in PlayableItem,
              on: pi.id == wf.playable_item_id and pi.container_type == :video_object,
              where: pi.container_id == parent_as(:entity).id and kf.state == "present",
              select: 1
            )
          ),
      order_by: [{:desc, v.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_hero_record/1)
  end

  # --- Private helpers for HomeLive facade ---

  # Fetches standalone movies with at least one incomplete WatchProgress record.
  # Returns `%{entity: entity_map, progress: progress_map, progress_records: [record]}`.
  #
  # Uses the by-record-count variant of `standalone_movies` so a transiently
  # absent file does not erase the user's intent to keep watching.
  defp fetch_in_progress_movies(limit) do
    movies =
      from([m] in PresentableQueries.standalone_movies_by_record_count(),
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              where:
                pi.container_type == ^:movie and pi.container_id == parent_as(:item).id and
                  wp.completed == false,
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at
                 FROM library_watch_progress wp
                 JOIN library_playable_items pi ON pi.id = wp.playable_item_id
                WHERE pi.container_type = 'movie' AND pi.container_id = ?
                LIMIT 1)
              """,
              m.id
            )
        ],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, :watch_progress])

    Enum.reject(Enum.map(movies, &build_in_progress_movie_entry/1), &is_nil/1)
  end

  # Fetches singleton-collection movies (the sole child Movie record of their
  # MovieSeries) with an incomplete WatchProgress record. Surfaces the child
  # movie at the top level instead of the collection container.
  #
  # Uses the by-record-count variant so categorization is stable against
  # transient file-presence changes — the user's engagement signal, not file
  # presence, drives row inclusion on this surface.
  defp fetch_in_progress_hoisted_movies(limit) do
    movies =
      from([m] in PresentableQueries.singleton_collection_movies_by_record_count(),
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              where:
                pi.container_type == ^:movie and pi.container_id == parent_as(:item).id and
                  wp.completed == false,
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at
                 FROM library_watch_progress wp
                 JOIN library_playable_items pi ON pi.id = wp.playable_item_id
                WHERE pi.container_type = 'movie' AND pi.container_id = ?
                LIMIT 1)
              """,
              m.id
            )
        ],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, :movie_series, :watch_progress])

    Enum.reject(Enum.map(movies, &build_in_progress_movie_entry/1), &is_nil/1)
  end

  defp build_in_progress_movie_entry(movie) do
    progress_records = if movie.watch_progress, do: [movie.watch_progress], else: []

    in_progress_records = Enum.reject(progress_records, & &1.completed)

    if in_progress_records != [] do
      entity = %{
        id: movie.id,
        type: :movie,
        name: movie.name,
        description: movie.description,
        images: movie.images || [],
        genres: movie.genres,
        duration_seconds: movie.duration_seconds
      }

      progress =
        Map.merge(
          %{
            episodes_completed:
              if(movie.watch_progress && movie.watch_progress.completed, do: 1, else: 0),
            episodes_total: 1
          },
          ContinueWatchingProgress.current_position_summary(progress_records)
        )

      %{entity: entity, progress: progress, progress_records: progress_records}
    end
  end

  # Fetches TV series that have at least one incomplete episode WatchProgress record.
  defp fetch_in_progress_tv_series(limit) do
    series_list =
      from(t in TVSeries,
        as: :series,
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              join: ep in "library_episodes",
              on: ep.id == pi.container_id and pi.container_type == ^:episode,
              join: s in "library_seasons",
              on: s.id == ep.season_id,
              where: s.tv_series_id == parent_as(:series).id,
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at FROM library_watch_progress wp
               JOIN library_playable_items pi ON pi.id = wp.playable_item_id
               JOIN library_episodes ep ON ep.id = pi.container_id AND pi.container_type = 'episode'
               JOIN library_seasons s ON s.id = ep.season_id
               WHERE s.tv_series_id = ?
               ORDER BY wp.last_watched_at DESC LIMIT 1)
              """,
              t.id
            )
        ],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, seasons: [:episodes]])

    all_episode_ids =
      for series <- series_list,
          season <- series.seasons || [],
          episode <- season.episodes || [],
          do: episode.id

    progress_by_episode_id =
      if all_episode_ids == [] do
        %{}
      else
        from(progress in WatchProgress,
          join: pi in PlayableItem,
          on: pi.id == progress.playable_item_id,
          where: pi.container_type == ^:episode and pi.container_id in ^all_episode_ids,
          select: {pi.container_id, progress}
        )
        |> Repo.all()
        |> Map.new()
      end

    Enum.reject(
      Enum.map(series_list, fn series ->
        episode_ids =
          for season <- series.seasons || [], episode <- season.episodes || [], do: episode.id

        progress_records =
          episode_ids
          |> Enum.map(&Map.get(progress_by_episode_id, &1))
          |> Enum.reject(&is_nil/1)

        episodes_total = length(episode_ids)
        episodes_completed = Enum.count(progress_records, & &1.completed)

        # Include series when the user has touched it (any progress) AND
        # hasn't finished all episodes — matches `LibraryProgress.in_progress?`
        # used by `/library?in_progress=1`.
        if progress_records != [] and episodes_completed < episodes_total do
          entity = %{
            id: series.id,
            type: :tv_series,
            name: series.name,
            description: series.description,
            images: series.images || [],
            genres: series.genres,
            duration_seconds: nil
          }

          progress =
            Map.merge(
              %{episodes_completed: episodes_completed, episodes_total: episodes_total},
              ContinueWatchingProgress.current_position_summary(progress_records)
            )

          %{entity: entity, progress: progress, progress_records: progress_records}
        end
      end),
      &is_nil/1
    )
  end

  # Fetches video objects with at least one incomplete WatchProgress record.
  defp fetch_in_progress_video_objects(limit) do
    video_objects =
      from(v in VideoObject,
        as: :video_object,
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              where:
                pi.container_type == ^:video_object and
                  pi.container_id == parent_as(:video_object).id and
                  wp.completed == false,
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at
                 FROM library_watch_progress wp
                 JOIN library_playable_items pi ON pi.id = wp.playable_item_id
                WHERE pi.container_type = 'video_object' AND pi.container_id = ?
                LIMIT 1)
              """,
              v.id
            )
        ],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, :watch_progress])

    Enum.reject(
      Enum.map(video_objects, fn video_object ->
        progress_records = if video_object.watch_progress, do: [video_object.watch_progress], else: []
        in_progress_records = Enum.reject(progress_records, & &1.completed)

        if in_progress_records != [] do
          entity = %{
            id: video_object.id,
            type: :video_object,
            name: video_object.name,
            description: video_object.description,
            images: video_object.images || [],
            genres: nil,
            duration_seconds: nil
          }

          progress =
            Map.merge(
              %{
                episodes_completed:
                  if(video_object.watch_progress && video_object.watch_progress.completed,
                    do: 1,
                    else: 0
                  ),
                episodes_total: 1
              },
              ContinueWatchingProgress.current_position_summary(progress_records)
            )

          %{entity: entity, progress: progress, progress_records: progress_records}
        end
      end),
      &is_nil/1
    )
  end

  # Fetches multi-child movie series where child movies have at least one
  # incomplete WatchProgress record. Singleton-collection movies are surfaced
  # via `fetch_in_progress_hoisted_movies/1` instead.
  #
  # Uses the by-record-count variant so a collection with 2+ children
  # categorizes consistently regardless of how many of those children have
  # present files right now.
  defp fetch_in_progress_movie_series(limit) do
    series_list =
      from([ms] in PresentableQueries.multi_child_movie_series_by_record_count(),
        where:
          exists(
            from(wp in WatchProgress,
              join: pi in PlayableItem,
              on: pi.id == wp.playable_item_id,
              join: m in Movie,
              on: m.id == pi.container_id and pi.container_type == ^:movie,
              where: m.movie_series_id == parent_as(:item).id,
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at FROM library_watch_progress wp
               JOIN library_playable_items pi ON pi.id = wp.playable_item_id
               JOIN library_movies m ON m.id = pi.container_id AND pi.container_type = 'movie'
               WHERE m.movie_series_id = ?
               ORDER BY wp.last_watched_at DESC LIMIT 1)
              """,
              ms.id
            )
        ],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, movies: [:watch_progress]])

    Enum.reject(
      Enum.map(series_list, fn series ->
        progress_records =
          for movie <- series.movies || [],
              progress = movie.watch_progress,
              not is_nil(progress),
              do: progress

        movies_total = length(series.movies || [])
        movies_completed = Enum.count(progress_records, & &1.completed)

        # Include movie series when the user has touched it AND hasn't
        # finished all child movies — matches `LibraryProgress.in_progress?`.
        if progress_records != [] and movies_completed < movies_total do
          entity = %{
            id: series.id,
            type: :movie_series,
            name: series.name,
            description: series.description,
            images: series.images || [],
            genres: series.genres,
            duration_seconds: nil
          }

          progress =
            Map.merge(
              %{episodes_completed: movies_completed, episodes_total: movies_total},
              ContinueWatchingProgress.current_position_summary(progress_records)
            )

          %{entity: entity, progress: progress, progress_records: progress_records}
        end
      end),
      &is_nil/1
    )
  end

  defp entry_last_watched_at(%{progress_records: records}) do
    records
    |> Enum.map(& &1.last_watched_at)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp shape_in_progress_row(%{entity: entity, progress: summary, progress_records: records}) do
    backdrop_url = image_url(entity.images, "backdrop")
    logo_url = image_url(entity.images, "logo")

    last_episode_label = progress_episode_label(entity, summary)

    progress_pct = ContinueWatchingProgress.compute_pct(summary)

    last_watched_at = entry_last_watched_at(%{progress_records: records})

    %{
      entity_id: entity.id,
      entity_name: entity.name,
      last_episode_label: last_episode_label,
      progress_pct: progress_pct,
      backdrop_url: backdrop_url,
      logo_url: logo_url,
      last_watched_at: last_watched_at
    }
  end

  defp progress_episode_label(%{type: :tv_series}, summary) when not is_nil(summary) do
    if summary.episodes_total > 1 do
      "#{summary.episodes_completed} / #{summary.episodes_total} episodes"
    end
  end

  defp progress_episode_label(%{type: :movie_series}, summary) when not is_nil(summary) do
    if summary.episodes_total > 1 do
      "#{summary.episodes_completed} / #{summary.episodes_total} movies"
    end
  end

  defp progress_episode_label(_entity, _summary), do: nil

  # Shapes a record (Movie, TVSeries, MovieSeries, VideoObject struct) into
  # the recently-added plain map. Carries `__inserted_at__` for merge-sort,
  # dropped by the caller before returning to HomeLive.
  defp shape_recently_added_record(record) do
    poster_url =
      case Enum.find(record.images || [], &(&1.role == "poster")) do
        %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
        _ -> nil
      end

    %{
      id: record.id,
      name: record.name,
      year: record_year(record),
      poster_url: poster_url,
      __inserted_at__: record.inserted_at
    }
  end

  # Shapes a record (Movie, TVSeries, MovieSeries, VideoObject struct with
  # images preloaded) into the hero candidate plain map.
  defp shape_hero_record(record) do
    backdrop_url = image_url(record.images, "backdrop")
    logo_url = image_url(record.images, "logo")

    runtime_minutes =
      case Map.get(record, :duration_seconds) do
        seconds when is_integer(seconds) and seconds > 0 -> div(seconds, 60)
        _ -> nil
      end

    %{
      id: record.id,
      name: record.name,
      year: record_year(record),
      runtime_minutes: runtime_minutes,
      genres: Map.get(record, :genres),
      overview: record.description,
      backdrop_url: backdrop_url,
      logo_url: logo_url
    }
  end

  # Extracts the year from a record's `date_published` field. Returns `nil`
  # when the record has no date or the field isn't a `%Date{}` (e.g. a plain
  # map shape from upstream callers).
  defp record_year(%{date_published: %Date{year: y}}), do: y
  defp record_year(_), do: nil

  defp image_url(images, role) do
    case Enum.find(images || [], &(&1.role == role)) do
      %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
      _ -> nil
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp destroy_bang!(record) do
    Repo.bang!(Repo.delete(record))
    :ok
  end

  defp maybe_preload(records, []), do: records
  defp maybe_preload(records, preloads), do: Repo.preload(records, preloads)

  # Find an existing record by `lookup` (a keyword list of field/value pairs)
  # or insert a new one from `attrs` via `schema.create_changeset/1`. Returns
  # the existing record unchanged on hit.
  defp find_or_insert_by(schema, lookup, attrs) do
    case existing_by(schema, lookup) do
      nil -> Repo.insert(schema.create_changeset(attrs))
      existing -> {:ok, existing}
    end
  end

  # Find an existing record by `lookup` (a keyword list of field/value pairs)
  # or insert a new one from `attrs`. Updates the existing record via
  # `schema.update_changeset/2` on hit. Used for progress upserts.
  defp upsert_by(schema, lookup, attrs) do
    case existing_by(schema, lookup) do
      nil -> Repo.insert(schema.create_changeset(attrs))
      existing -> Repo.update(schema.update_changeset(existing, attrs))
    end
  end

  # `Repo.get_by(Schema, key: nil)` matches the first row whose key is NULL,
  # silently corrupting partial-input requests. Treat any nil lookup value as
  # "no match" and fall through to insert; the changeset will validate
  # required fields.
  defp existing_by(schema, lookup) do
    if !Enum.any?(lookup, fn {_key, value} -> is_nil(value) end) do
      Repo.get_by(schema, lookup)
    end
  end

  defp lookup_attr(attrs, key) when is_atom(key) do
    attrs[key] || attrs[Atom.to_string(key)]
  end
end
