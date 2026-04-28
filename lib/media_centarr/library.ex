defmodule MediaCentarr.Library do
  use Boundary,
    deps: [],
    exports: [
      Availability,
      Browser,
      EntityShape,
      Episode,
      EpisodeList,
      ExternalId,
      FileEventHandler,
      Image,
      ImageHealth,
      Movie,
      MovieList,
      MovieSeries,
      ProgressSummary,
      Season,
      TVSeries,
      TypeResolver,
      VideoObject,
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
    Episode,
    Extra,
    ExtraProgress,
    ExternalId,
    Image,
    Movie,
    MovieSeries,
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

  def get_tv_series(id) do
    case Repo.get(TVSeries, id) do
      nil -> {:error, :not_found}
      tv_series -> {:ok, tv_series}
    end
  end

  def get_tv_series!(id), do: Repo.get!(TVSeries, id)

  def get_tv_series_with_associations(id) do
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

  def get_movie_series(id) do
    case Repo.get(MovieSeries, id) do
      nil -> {:error, :not_found}
      movie_series -> {:ok, movie_series}
    end
  end

  def get_movie_series!(id), do: Repo.get!(MovieSeries, id)

  def get_movie_series_with_associations(id) do
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

  def get_video_object(id) do
    case Repo.get(VideoObject, id) do
      nil -> {:error, :not_found}
      video_object -> {:ok, video_object}
    end
  end

  def get_video_object!(id), do: Repo.get!(VideoObject, id)

  def get_video_object_with_associations(id) do
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
    {:ok, Repo.all(from(w in WatchedFile, where: w.file_path in ^file_paths))}
  end

  def list_files_by_paths!(file_paths), do: Repo.bang!(list_files_by_paths(file_paths))

  @doc """
  Lists watched files where any type-specific FK matches the given ID.
  Used when you have an entity UUID but don't know which type table it lives in.
  """
  def list_watched_files_by_entity_id(entity_id) do
    Repo.all(
      from(w in WatchedFile,
        where:
          w.movie_id == ^entity_id or w.tv_series_id == ^entity_id or
            w.movie_series_id == ^entity_id or w.video_object_id == ^entity_id
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
  Lists extras by any type-specific FK matching the given ID.
  """
  def list_extras_by_owner_id(owner_id) do
    Repo.all(
      from(x in Extra,
        where: x.tv_series_id == ^owner_id or x.movie_series_id == ^owner_id or x.movie_id == ^owner_id
      )
    )
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
            x.tv_series_id == ^owner_id or
              (not is_nil(x.season_id) and x.season_id in ^season_ids)
        )
      )

    {entity_extras, season_extras_by_id} = split_extras_by_season(all_extras)

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

  defp split_extras_by_season(extras) do
    {entity_extras, season_extras} = Enum.split_with(extras, &is_nil(&1.season_id))
    season_extras_by_id = Enum.group_by(season_extras, & &1.season_id)
    {entity_extras, season_extras_by_id}
  end

  # ---------------------------------------------------------------------------
  # Image
  # ---------------------------------------------------------------------------

  def list_all_images, do: Repo.all(Image)

  def create_image(attrs) do
    Repo.insert(Image.create_changeset(attrs))
  end

  def create_image!(attrs), do: Repo.bang!(create_image(attrs))

  def upsert_image(attrs, conflict_target) do
    Repo.insert(Image.create_changeset(attrs),
      on_conflict: {:replace, [:content_url, :extension, :updated_at]},
      conflict_target: conflict_target
    )
  end

  def update_image(image, attrs) do
    Repo.update(Image.update_changeset(image, attrs))
  end

  def update_image!(image, attrs), do: Repo.bang!(update_image(image, attrs))

  def destroy_image(image), do: Repo.delete(image)
  def destroy_image!(image), do: destroy_bang!(image)

  # ---------------------------------------------------------------------------
  # ExternalId
  # ---------------------------------------------------------------------------

  def find_or_create_external_id(attrs) do
    source = attrs[:source] || attrs["source"]
    external_id = attrs[:external_id] || attrs["external_id"]

    case Repo.get_by(ExternalId, source: source, external_id: external_id) do
      nil -> Repo.insert(ExternalId.create_changeset(attrs))
      existing -> {:ok, existing}
    end
  end

  def find_or_create_external_id!(attrs), do: Repo.bang!(find_or_create_external_id(attrs))

  def create_external_id(attrs) do
    Repo.insert(ExternalId.create_changeset(attrs))
  end

  def create_external_id!(attrs), do: Repo.bang!(create_external_id(attrs))

  def destroy_external_id(external_id), do: Repo.delete(external_id)
  def destroy_external_id!(external_id), do: destroy_bang!(external_id)

  def find_by_tmdb_id_for_movie(tmdb_id) do
    {:ok,
     Repo.one(
       from(i in ExternalId,
         where: i.source == "tmdb" and i.external_id == ^tmdb_id and not is_nil(i.movie_id),
         limit: 1
       )
     )}
  end

  def find_by_tmdb_id_for_tv_series(tmdb_id) do
    {:ok,
     Repo.one(
       from(i in ExternalId,
         where: i.source == "tmdb" and i.external_id == ^tmdb_id and not is_nil(i.tv_series_id),
         limit: 1
       )
     )}
  end

  def find_by_tmdb_collection_for_movie_series(collection_id) do
    {:ok,
     Repo.one(
       from(i in ExternalId,
         where:
           i.source == "tmdb_collection" and i.external_id == ^collection_id and
             not is_nil(i.movie_series_id),
         limit: 1
       )
     )}
  end

  @doc """
  Returns `{tv_series_id, external_id}` pairs for TV series in the given list
  that have a TMDB external identifier.
  """
  def tmdb_external_ids_for_tv_series(tv_series_ids) when is_list(tv_series_ids) do
    Repo.all(
      from(ext in ExternalId,
        where: ext.tv_series_id in ^tv_series_ids and ext.source == "tmdb",
        select: {ext.tv_series_id, ext.external_id}
      )
    )
  end

  @doc """
  Returns every TMDB-style external ID in the library with its owning FK columns.
  Includes both `"tmdb"` (movies, TV, standalone movies) and `"tmdb_collection"`
  (movie series) sources. Used by ReleaseTracking to scan for tracking candidates.
  """
  def list_tmdb_external_ids do
    Repo.all(
      from(ext in ExternalId,
        where: ext.source in ["tmdb", "tmdb_collection"],
        select: %{
          source: ext.source,
          external_id: ext.external_id,
          tv_series_id: ext.tv_series_id,
          movie_series_id: ext.movie_series_id,
          movie_id: ext.movie_id
        }
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Movie
  # ---------------------------------------------------------------------------

  def list_movies, do: Repo.all(Movie)

  def get_movie(id) do
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

  def get_movie_with_associations(id) do
    case Repo.get(Movie, id) do
      nil -> {:error, :not_found}
      movie -> {:ok, Repo.preload(movie, @movie_full_preloads)}
    end
  end

  def get_movie_with_associations!(id) do
    Repo.preload(Repo.get!(Movie, id), @movie_full_preloads)
  end

  def find_or_create_movie_for_series(attrs) do
    movie_series_id = attrs[:movie_series_id] || attrs["movie_series_id"]
    tmdb_id = attrs[:tmdb_id] || attrs["tmdb_id"]

    case Repo.get_by(Movie, movie_series_id: movie_series_id, tmdb_id: tmdb_id) do
      nil -> Repo.insert(Movie.create_changeset(attrs))
      existing -> {:ok, existing}
    end
  end

  def list_movies_for_series(movie_series_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    result =
      from(m in Movie, where: m.movie_series_id == ^movie_series_id)
      |> Repo.all()
      |> maybe_preload(preloads)

    {:ok, result}
  end

  # ---------------------------------------------------------------------------
  # Extra
  # ---------------------------------------------------------------------------

  def list_extras_for_season(season_id) do
    {:ok, Repo.all(from(x in Extra, where: x.season_id == ^season_id))}
  end

  def list_extras_for_season!(season_id), do: Repo.bang!(list_extras_for_season(season_id))

  def get_extra(id) do
    case Repo.get(Extra, id) do
      nil -> {:error, :not_found}
      extra -> {:ok, extra}
    end
  end

  def get_extra!(id), do: Repo.get!(Extra, id)

  @doc """
  Find or create an extra by type-specific FK + content_url.
  The `type_fk` is the FK key atom (e.g. `:movie_id`, `:tv_series_id`).
  """
  def find_or_create_extra_by_type(attrs, type_fk) do
    owner_id = attrs[type_fk] || attrs[Atom.to_string(type_fk)]
    content_url = attrs[:content_url] || attrs["content_url"]

    existing =
      if owner_id && content_url do
        Repo.get_by(Extra, [{type_fk, owner_id}, {:content_url, content_url}])
      end

    case existing do
      nil -> Repo.insert(Extra.create_changeset(attrs))
      record -> {:ok, record}
    end
  end

  def create_extra(attrs) do
    Repo.insert(Extra.create_changeset(attrs))
  end

  def create_extra!(attrs), do: Repo.bang!(create_extra(attrs))

  def destroy_extra(extra), do: Repo.delete(extra)
  def destroy_extra!(extra), do: destroy_bang!(extra)

  # ---------------------------------------------------------------------------
  # Season
  # ---------------------------------------------------------------------------

  def list_seasons, do: Repo.all(Season)

  def get_season(id) do
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
    tv_series_id = attrs[:tv_series_id] || attrs["tv_series_id"]
    season_number = attrs[:season_number] || attrs["season_number"]

    existing =
      if tv_series_id && season_number do
        Repo.get_by(Season, tv_series_id: tv_series_id, season_number: season_number)
      end

    case existing do
      nil -> Repo.insert(Season.create_changeset(attrs))
      record -> {:ok, record}
    end
  end

  def list_seasons_for_tv_series(tv_series_id) do
    {:ok, Repo.all(from(s in Season, where: s.tv_series_id == ^tv_series_id))}
  end

  # ---------------------------------------------------------------------------
  # Episode
  # ---------------------------------------------------------------------------

  def list_episodes, do: Repo.all(Episode)

  def list_episodes_for_season(season_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    result =
      from(e in Episode, where: e.season_id == ^season_id)
      |> Repo.all()
      |> maybe_preload(preloads)

    {:ok, result}
  end

  def list_episodes_for_season!(season_id, opts \\ []) do
    Repo.bang!(list_episodes_for_season(season_id, opts))
  end

  def get_episode(id) do
    case Repo.get(Episode, id) do
      nil -> {:error, :not_found}
      episode -> {:ok, episode}
    end
  end

  def get_episode!(id), do: Repo.get!(Episode, id)

  def find_or_create_episode(attrs) do
    season_id = attrs[:season_id] || attrs["season_id"]
    episode_number = attrs[:episode_number] || attrs["episode_number"]

    case Repo.get_by(Episode, season_id: season_id, episode_number: episode_number) do
      nil -> Repo.insert(Episode.create_changeset(attrs))
      existing -> {:ok, existing}
    end
  end

  def find_or_create_episode!(attrs), do: Repo.bang!(find_or_create_episode(attrs))

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
  Gets a watch progress record by a specific FK key and value.
  """
  def get_watch_progress_by_fk(fk_key, fk_id) do
    case Repo.get_by(WatchProgress, [{fk_key, fk_id}]) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  def find_or_create_watch_progress_for_movie(attrs) do
    movie_id = attrs[:movie_id] || attrs["movie_id"]

    case Repo.get_by(WatchProgress, movie_id: movie_id) do
      nil -> Repo.insert(WatchProgress.upsert_changeset(attrs))
      existing -> Repo.update(WatchProgress.update_changeset(existing, attrs))
    end
  end

  def find_or_create_watch_progress_for_episode(attrs) do
    episode_id = attrs[:episode_id] || attrs["episode_id"]

    case Repo.get_by(WatchProgress, episode_id: episode_id) do
      nil -> Repo.insert(WatchProgress.upsert_changeset(attrs))
      existing -> Repo.update(WatchProgress.update_changeset(existing, attrs))
    end
  end

  def find_or_create_watch_progress_for_video_object(attrs) do
    video_object_id = attrs[:video_object_id] || attrs["video_object_id"]

    case Repo.get_by(WatchProgress, video_object_id: video_object_id) do
      nil -> Repo.insert(WatchProgress.upsert_changeset(attrs))
      existing -> Repo.update(WatchProgress.update_changeset(existing, attrs))
    end
  end

  # ---------------------------------------------------------------------------
  # ExtraProgress
  # ---------------------------------------------------------------------------

  def get_extra_progress_by_extra(extra_id) do
    {:ok, Repo.get_by(ExtraProgress, extra_id: extra_id)}
  end

  def find_or_create_extra_progress(attrs) do
    extra_id = attrs[:extra_id] || attrs["extra_id"]

    case Repo.get_by(ExtraProgress, extra_id: extra_id) do
      nil ->
        Repo.insert(ExtraProgress.upsert_changeset(attrs))

      existing ->
        Repo.update(ExtraProgress.update_changeset(existing, attrs))
    end
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

    {:ok, Repo.all(query)}
  end

  def list_recent_changes!(limit, since), do: Repo.bang!(list_recent_changes(limit, since))

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

  Issues at most ~15 targeted queries regardless of library size, compared to
  the ~87 queries of the previous `fetch_all_typed_entries` approach.
  """
  @spec list_in_progress(keyword()) :: [map()]
  def list_in_progress(opts \\ []) do
    limit = Keyword.get(opts, :limit, 12)

    movie_entries = fetch_in_progress_movies(limit)
    tv_series_entries = fetch_in_progress_tv_series(limit)
    video_object_entries = fetch_in_progress_video_objects(limit)
    movie_series_entries = fetch_in_progress_movie_series(limit)

    (movie_entries ++ tv_series_entries ++ video_object_entries ++ movie_series_entries)
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
    tv_series = fetch_recently_added_tv_series(limit)
    movie_series = fetch_recently_added_movie_series(limit)
    video_objects = fetch_recently_added_video_objects(limit)

    (movies ++ tv_series ++ movie_series ++ video_objects)
    |> Enum.sort_by(& &1.__inserted_at__, {:desc, DateTime})
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :__inserted_at__))
  end

  defp fetch_recently_added_movies(limit) do
    from(m in Movie,
      as: :item,
      where:
        is_nil(m.movie_series_id) and
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.movie_id == parent_as(:item).id and kf.state == "present",
              select: 1
            )
          ),
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
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in "watcher_files",
            on: kf.file_path == wf.file_path,
            where: wf.tv_series_id == parent_as(:item).id and kf.state == "present",
            select: 1
          )
        ),
      order_by: [{:desc, t.inserted_at}],
      limit: ^limit
    )
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(&shape_recently_added_record/1)
  end

  defp fetch_recently_added_movie_series(limit) do
    from(ms in MovieSeries,
      as: :item,
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in "watcher_files",
            on: kf.file_path == wf.file_path,
            where: wf.movie_series_id == parent_as(:item).id and kf.state == "present",
            select: 1
          )
        ),
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
      where:
        exists(
          from(wf in "library_watched_files",
            join: kf in "watcher_files",
            on: kf.file_path == wf.file_path,
            where: wf.video_object_id == parent_as(:item).id and kf.state == "present",
            select: 1
          )
        ),
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
    tv_series = fetch_hero_candidates_tv_series(limit)
    movie_series = fetch_hero_candidates_movie_series(limit)
    video_objects = fetch_hero_candidates_video_objects(limit)

    Enum.take(movies ++ tv_series ++ movie_series ++ video_objects, limit)
  end

  @doc """
  Look up display info for a list of entities given their types and IDs.
  Used by HomeLive's Heavy Rotation row to enrich rewatch counts.

  Takes a list of `{entity_type, entity_id}` tuples where `entity_type` is
  one of `:movie`, `:episode`, or `:video_object`. Returns a map keyed by
  `{entity_type, entity_id}` with values `%{id, name, year, poster_url}`.

  For episodes, the display name and poster come from the parent TV series.
  Missing or unknown IDs are silently omitted from the result.
  """
  @spec lookup_entities_for_display([{atom(), term()}]) :: %{{atom(), term()} => map()}
  def lookup_entities_for_display(refs) do
    refs
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.flat_map(fn {type, ids} -> fetch_display_records(type, ids) end)
    |> Map.new()
  end

  # --- Private fetchers for list_hero_candidates ---

  defp fetch_hero_candidates_movies(limit) do
    from(m in Movie,
      as: :entity,
      where:
        is_nil(m.movie_series_id) and
          not is_nil(m.description) and
          fragment("TRIM(?)", m.description) != "" and
          exists(
            from(img in Image,
              where:
                img.movie_id == parent_as(:entity).id and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ) and
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.movie_id == parent_as(:entity).id and kf.state == "present",
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
                img.tv_series_id == parent_as(:entity).id and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ) and
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.tv_series_id == parent_as(:entity).id and kf.state == "present",
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
    from(ms in MovieSeries,
      as: :entity,
      where:
        not is_nil(ms.description) and
          fragment("TRIM(?)", ms.description) != "" and
          exists(
            from(img in Image,
              where:
                img.movie_series_id == parent_as(:entity).id and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ) and
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.movie_series_id == parent_as(:entity).id and kf.state == "present",
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
                img.video_object_id == parent_as(:entity).id and
                  img.role == "backdrop" and
                  not is_nil(img.content_url),
              select: 1
            )
          ) and
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.video_object_id == parent_as(:entity).id and kf.state == "present",
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
  defp fetch_in_progress_movies(limit) do
    movies =
      from(m in Movie,
        as: :movie,
        where: is_nil(m.movie_series_id),
        where:
          exists(
            from(wp in WatchProgress,
              where: wp.movie_id == parent_as(:movie).id and wp.completed == false,
              select: 1
            )
          ),
        where:
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.movie_id == parent_as(:movie).id and kf.state == "present",
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              "(SELECT last_watched_at FROM library_watch_progress WHERE movie_id = ? LIMIT 1)",
              m.id
            )
        ],
        limit: ^limit
      )
      |> Repo.all()
      |> Repo.preload([:images, :watch_progress])

    Enum.reject(
      Enum.map(movies, fn movie ->
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
            duration: movie.duration
          }

          progress = %{
            episodes_completed:
              if(movie.watch_progress && movie.watch_progress.completed, do: 1, else: 0),
            episodes_total: 1
          }

          %{entity: entity, progress: progress, progress_records: progress_records}
        end
      end),
      &is_nil/1
    )
  end

  # Fetches TV series that have at least one incomplete episode WatchProgress record.
  defp fetch_in_progress_tv_series(limit) do
    series_list =
      from(t in TVSeries,
        as: :series,
        where:
          exists(
            from(wp in WatchProgress,
              join: ep in "library_episodes",
              on: ep.id == wp.episode_id,
              join: s in "library_seasons",
              on: s.id == ep.season_id,
              where: s.tv_series_id == parent_as(:series).id and wp.completed == false,
              select: 1
            )
          ),
        where:
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.tv_series_id == parent_as(:series).id and kf.state == "present",
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at FROM library_watch_progress wp
               JOIN library_episodes ep ON ep.id = wp.episode_id
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
        from(progress in WatchProgress, where: progress.episode_id in ^all_episode_ids)
        |> Repo.all()
        |> Map.new(fn progress -> {progress.episode_id, progress} end)
      end

    Enum.reject(
      Enum.map(series_list, fn series ->
        episode_ids =
          for season <- series.seasons || [], episode <- season.episodes || [], do: episode.id

        progress_records =
          episode_ids
          |> Enum.map(&Map.get(progress_by_episode_id, &1))
          |> Enum.reject(&is_nil/1)

        in_progress_records = Enum.reject(progress_records, & &1.completed)

        if in_progress_records != [] do
          episodes_total = length(episode_ids)
          episodes_completed = Enum.count(progress_records, & &1.completed)

          entity = %{
            id: series.id,
            type: :tv_series,
            name: series.name,
            description: series.description,
            images: series.images || [],
            genres: series.genres,
            duration: nil
          }

          progress = %{episodes_completed: episodes_completed, episodes_total: episodes_total}

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
              where: wp.video_object_id == parent_as(:video_object).id and wp.completed == false,
              select: 1
            )
          ),
        where:
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              where: wf.video_object_id == parent_as(:video_object).id and kf.state == "present",
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              "(SELECT last_watched_at FROM library_watch_progress WHERE video_object_id = ? LIMIT 1)",
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
            duration: nil
          }

          progress = %{
            episodes_completed:
              if(video_object.watch_progress && video_object.watch_progress.completed, do: 1, else: 0),
            episodes_total: 1
          }

          %{entity: entity, progress: progress, progress_records: progress_records}
        end
      end),
      &is_nil/1
    )
  end

  # Fetches movie series where child movies have at least one incomplete WatchProgress record.
  defp fetch_in_progress_movie_series(limit) do
    series_list =
      from(ms in MovieSeries,
        as: :series,
        where:
          exists(
            from(wp in WatchProgress,
              join: m in Movie,
              on: m.id == wp.movie_id,
              where: m.movie_series_id == parent_as(:series).id and wp.completed == false,
              select: 1
            )
          ),
        where:
          exists(
            from(wf in "library_watched_files",
              join: kf in "watcher_files",
              on: kf.file_path == wf.file_path,
              join: m in "library_movies",
              on: m.id == wf.movie_id,
              where: m.movie_series_id == parent_as(:series).id and kf.state == "present",
              select: 1
            )
          ),
        order_by: [
          desc:
            fragment(
              """
              (SELECT wp.last_watched_at FROM library_watch_progress wp
               JOIN library_movies m ON m.id = wp.movie_id
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

        in_progress_records = Enum.reject(progress_records, & &1.completed)

        if in_progress_records != [] do
          movies_total = length(series.movies || [])
          movies_completed = Enum.count(progress_records, & &1.completed)

          entity = %{
            id: series.id,
            type: :movie_series,
            name: series.name,
            description: series.description,
            images: series.images || [],
            genres: series.genres,
            duration: nil
          }

          progress = %{episodes_completed: movies_completed, episodes_total: movies_total}

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
    backdrop_url =
      case Enum.find(entity.images || [], &(&1.role == "backdrop")) do
        %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
        _ -> nil
      end

    last_episode_label = progress_episode_label(entity, summary)

    progress_pct =
      if summary && summary.episodes_total > 0 do
        completed_fraction = summary.episodes_completed / summary.episodes_total
        trunc(completed_fraction * 100)
      else
        0
      end

    last_watched_at = entry_last_watched_at(%{progress_records: records})

    %{
      entity_id: entity.id,
      entity_name: entity.name,
      last_episode_label: last_episode_label,
      progress_pct: progress_pct,
      backdrop_url: backdrop_url,
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

  # --- Private fetchers for lookup_entities_for_display ---

  # Movies: batch-query by IDs, preload images, shape into display maps.
  defp fetch_display_records(:movie, ids) do
    Movie
    |> where([m], m.id in ^ids)
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(fn movie ->
      poster_url =
        case Enum.find(movie.images || [], &(&1.role == "poster")) do
          %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
          _ -> nil
        end

      year =
        case movie.date_published do
          <<year::binary-size(4), _::binary>> -> year
          _ -> nil
        end

      {{:movie, movie.id}, %{id: movie.id, name: movie.name, year: year, poster_url: poster_url}}
    end)
  end

  # Episodes: batch-query by IDs, join through season → tv_series for display
  # name and poster. The TV series name + poster is more recognisable than the
  # individual episode name on a small poster card.
  defp fetch_display_records(:episode, ids) do
    Episode
    |> where([episode], episode.id in ^ids)
    |> Repo.all()
    |> Repo.preload(season: [tv_series: :images])
    |> Enum.map(fn episode ->
      tv_series = episode.season && episode.season.tv_series

      {name, year, poster_url} =
        if tv_series do
          poster =
            case Enum.find(tv_series.images || [], &(&1.role == "poster")) do
              %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
              _ -> nil
            end

          year =
            case tv_series.date_published do
              <<year_str::binary-size(4), _::binary>> -> year_str
              _ -> nil
            end

          {tv_series.name, year, poster}
        else
          {episode.name, nil, nil}
        end

      {{:episode, episode.id}, %{id: episode.id, name: name, year: year, poster_url: poster_url}}
    end)
  end

  # VideoObjects: batch-query by IDs, preload images, shape into display maps.
  defp fetch_display_records(:video_object, ids) do
    VideoObject
    |> where([video_object], video_object.id in ^ids)
    |> Repo.all()
    |> Repo.preload(:images)
    |> Enum.map(fn video_object ->
      poster_url =
        case Enum.find(video_object.images || [], &(&1.role == "poster")) do
          %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
          _ -> nil
        end

      year =
        case video_object.date_published do
          <<year::binary-size(4), _::binary>> -> year
          _ -> nil
        end

      {{:video_object, video_object.id},
       %{id: video_object.id, name: video_object.name, year: year, poster_url: poster_url}}
    end)
  end

  # Unknown entity types produce no results.
  defp fetch_display_records(_type, _ids), do: []

  # Shapes a record (Movie, TVSeries, MovieSeries, VideoObject struct) into
  # the recently-added plain map. Carries `__inserted_at__` for merge-sort,
  # dropped by the caller before returning to HomeLive.
  defp shape_recently_added_record(record) do
    poster_url =
      case Enum.find(record.images || [], &(&1.role == "poster")) do
        %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
        _ -> nil
      end

    year =
      case Map.get(record, :date_published) do
        <<year::binary-size(4), _::binary>> -> String.to_integer(year)
        _ -> nil
      end

    %{
      id: record.id,
      name: record.name,
      year: year,
      poster_url: poster_url,
      __inserted_at__: record.inserted_at
    }
  end

  # Shapes a record (Movie, TVSeries, MovieSeries, VideoObject struct with
  # images preloaded) into the hero candidate plain map.
  defp shape_hero_record(record) do
    backdrop_url =
      case Enum.find(record.images || [], &(&1.role == "backdrop")) do
        %{content_url: url} when is_binary(url) -> "/media-images/#{url}"
        _ -> nil
      end

    year =
      case Map.get(record, :date_published) do
        <<year::binary-size(4), _::binary>> -> String.to_integer(year)
        _ -> nil
      end

    runtime_minutes =
      case Map.get(record, :duration) do
        duration when is_binary(duration) ->
          case Integer.parse(duration) do
            {minutes, _} -> minutes
            _ -> nil
          end

        _ ->
          nil
      end

    %{
      id: record.id,
      name: record.name,
      year: year,
      runtime_minutes: runtime_minutes,
      genres: Map.get(record, :genres),
      overview: record.description,
      backdrop_url: backdrop_url
    }
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
end
