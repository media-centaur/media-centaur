defmodule MediaCentaur.Library do
  @moduledoc """
  The media library context — entities, images, identifiers, seasons, episodes,
  and watched files that flow through the ingestion pipeline.
  """
  import Ecto.Query

  alias MediaCentaur.Repo

  alias MediaCentaur.Library.{
    ChangeEntry,
    Entity,
    Episode,
    Extra,
    ExtraProgress,
    Identifier,
    Image,
    Movie,
    MovieSeries,
    Season,
    TVSeries,
    VideoObject,
    WatchProgress,
    WatchedFile
  }

  @full_preloads [
    :images,
    :identifiers,
    :watch_progress,
    :extras,
    :extra_progress,
    seasons: [:extras, episodes: :images],
    movies: :images
  ]

  @progress_preloads [
    :watch_progress,
    seasons: :episodes,
    movies: []
  ]

  @image_preloads [
    :images,
    seasons: [episodes: :images],
    movies: :images
  ]

  @tv_series_full_preloads [
    :images,
    :identifiers,
    :extras,
    :watched_files,
    seasons: [:extras, episodes: [:images, :watch_progress]]
  ]

  @movie_series_full_preloads [
    :images,
    :identifiers,
    :extras,
    :watched_files,
    movies: [:images, :watch_progress]
  ]

  @movie_full_preloads [
    :images,
    :identifiers,
    :extras,
    :watched_files,
    :watch_progress
  ]

  @video_object_full_preloads [
    :images,
    :identifiers,
    :watched_files,
    :watch_progress
  ]

  # ---------------------------------------------------------------------------
  # Entity
  # ---------------------------------------------------------------------------

  def list_entities, do: {:ok, Repo.all(Entity)}
  def list_entities!, do: Repo.all(Entity)

  def get_entity(id) do
    case Repo.get(Entity, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, entity}
    end
  end

  def get_entity!(id), do: Repo.get!(Entity, id)

  def list_entities_with_associations(opts \\ []) do
    query = Keyword.get(opts, :query, Entity)
    sort = Keyword.get(opts, :sort, asc: :name)

    entities =
      query
      |> order_by(^sort)
      |> Repo.all()
      |> Repo.preload(@full_preloads)

    {:ok, entities}
  end

  def list_entities_with_associations!(opts \\ []) do
    bang!(list_entities_with_associations(opts))
  end

  def get_entity_with_associations(id) do
    case Repo.get(Entity, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, Repo.preload(entity, @full_preloads)}
    end
  end

  def get_entity_with_associations!(id) do
    Repo.get!(Entity, id) |> Repo.preload(@full_preloads)
  end

  def get_entity_with_progress(id) do
    case Repo.get(Entity, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, Repo.preload(entity, @progress_preloads)}
    end
  end

  def get_entity_with_progress!(id) do
    Repo.get!(Entity, id) |> Repo.preload(@progress_preloads)
  end

  def list_entities_with_images(opts \\ []) do
    extra = Keyword.get(opts, :load, [])

    query =
      case Keyword.get(opts, :ids) do
        nil -> Entity
        ids -> from(e in Entity, where: e.id in ^ids)
      end

    entities =
      query
      |> Repo.all()
      |> Repo.preload(@image_preloads ++ extra)

    {:ok, entities}
  end

  def list_entities_with_images!(opts \\ []), do: bang!(list_entities_with_images(opts))

  def get_entity_with_images(id) do
    case Repo.get(Entity, id) do
      nil -> {:error, :not_found}
      entity -> {:ok, Repo.preload(entity, @image_preloads)}
    end
  end

  def get_entity_with_images!(id) do
    Repo.get!(Entity, id) |> Repo.preload(@image_preloads)
  end

  def list_entities_by_ids(ids, opts \\ []) do
    query = from(e in Entity, where: e.id in ^ids)

    query =
      case Keyword.get(opts, :filter_fn) do
        nil -> query
        filter_fn -> filter_fn.(query)
      end

    entities =
      query
      |> Repo.all()
      |> Repo.preload(@full_preloads)

    {:ok, entities}
  end

  def list_entities_by_ids!(ids, opts \\ []), do: bang!(list_entities_by_ids(ids, opts))

  def create_entity(attrs) do
    Entity.create_changeset(attrs) |> Repo.insert()
  end

  def create_entity!(attrs), do: bang!(create_entity(attrs))

  def set_entity_content_url(entity, attrs) do
    Entity.set_content_url_changeset(entity, attrs) |> Repo.update()
  end

  def set_entity_content_url!(entity, attrs), do: bang!(set_entity_content_url(entity, attrs))

  def destroy_entity(entity), do: Repo.delete(entity)
  def destroy_entity!(entity), do: destroy_bang!(entity)

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
    Repo.get!(TVSeries, id) |> Repo.preload(@tv_series_full_preloads)
  end

  def create_tv_series(attrs) do
    TVSeries.create_changeset(attrs) |> Repo.insert()
  end

  def create_tv_series!(attrs), do: bang!(create_tv_series(attrs))

  def update_tv_series(tv_series, attrs) do
    TVSeries.update_changeset(tv_series, attrs) |> Repo.update()
  end

  def update_tv_series!(tv_series, attrs), do: bang!(update_tv_series(tv_series, attrs))

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
    Repo.get!(MovieSeries, id) |> Repo.preload(@movie_series_full_preloads)
  end

  def create_movie_series(attrs) do
    MovieSeries.create_changeset(attrs) |> Repo.insert()
  end

  def create_movie_series!(attrs), do: bang!(create_movie_series(attrs))

  def update_movie_series(movie_series, attrs) do
    MovieSeries.update_changeset(movie_series, attrs) |> Repo.update()
  end

  def update_movie_series!(movie_series, attrs),
    do: bang!(update_movie_series(movie_series, attrs))

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
    Repo.get!(VideoObject, id) |> Repo.preload(@video_object_full_preloads)
  end

  def create_video_object(attrs) do
    VideoObject.create_changeset(attrs) |> Repo.insert()
  end

  def create_video_object!(attrs), do: bang!(create_video_object(attrs))

  def update_video_object(video_object, attrs) do
    VideoObject.update_changeset(video_object, attrs) |> Repo.update()
  end

  def update_video_object!(video_object, attrs),
    do: bang!(update_video_object(video_object, attrs))

  def destroy_video_object(video_object), do: Repo.delete(video_object)
  def destroy_video_object!(video_object), do: destroy_bang!(video_object)

  # ---------------------------------------------------------------------------
  # WatchedFile
  # ---------------------------------------------------------------------------

  def list_watched_files, do: {:ok, Repo.all(WatchedFile)}
  def list_watched_files!, do: Repo.all(WatchedFile)

  def list_watched_files_for_entity(entity_id) do
    {:ok, from(w in WatchedFile, where: w.entity_id == ^entity_id) |> Repo.all()}
  end

  def list_watched_files_for_entity!(entity_id) do
    from(w in WatchedFile, where: w.entity_id == ^entity_id) |> Repo.all()
  end

  def link_file(attrs) do
    file_path = attrs[:file_path] || attrs["file_path"]

    case Repo.get_by(WatchedFile, file_path: file_path) do
      nil -> WatchedFile.link_file_changeset(attrs) |> Repo.insert()
      existing -> WatchedFile.link_file_changeset(existing, attrs) |> Repo.update()
    end
  end

  def link_file!(attrs), do: bang!(link_file(attrs))

  def list_files_by_paths(file_paths) do
    {:ok, from(w in WatchedFile, where: w.file_path in ^file_paths) |> Repo.all()}
  end

  def list_files_by_paths!(file_paths), do: bang!(list_files_by_paths(file_paths))

  # ---------------------------------------------------------------------------
  # Image
  # ---------------------------------------------------------------------------

  def list_images, do: {:ok, Repo.all(Image)}
  def list_images!, do: Repo.all(Image)

  def create_image(attrs) do
    Image.create_changeset(attrs) |> Repo.insert()
  end

  def create_image!(attrs), do: bang!(create_image(attrs))

  def upsert_image(attrs, conflict_target) do
    Image.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:content_url, :extension, :updated_at]},
      conflict_target: conflict_target
    )
  end

  def update_image(image, attrs) do
    Image.update_changeset(image, attrs) |> Repo.update()
  end

  def update_image!(image, attrs), do: bang!(update_image(image, attrs))

  def destroy_image(image), do: Repo.delete(image)
  def destroy_image!(image), do: destroy_bang!(image)

  # ---------------------------------------------------------------------------
  # Identifier
  # ---------------------------------------------------------------------------

  def find_or_create_identifier(attrs) do
    property_id = attrs[:property_id] || attrs["property_id"]
    value = attrs[:value] || attrs["value"]

    case Repo.get_by(Identifier, property_id: property_id, value: value) do
      nil -> Identifier.create_changeset(attrs) |> Repo.insert()
      existing -> {:ok, existing}
    end
  end

  def find_or_create_identifier!(attrs), do: bang!(find_or_create_identifier(attrs))

  def find_by_tmdb_id(tmdb_id) do
    result =
      from(i in Identifier,
        where: i.property_id == "tmdb" and i.value == ^tmdb_id,
        limit: 1,
        preload: [:entity]
      )
      |> Repo.one()

    {:ok, result}
  end

  def find_by_tmdb_collection(collection_id) do
    result =
      from(i in Identifier,
        where: i.property_id == "tmdb_collection" and i.value == ^collection_id,
        limit: 1,
        preload: [:entity]
      )
      |> Repo.one()

    {:ok, result}
  end

  def create_identifier(attrs) do
    Identifier.create_changeset(attrs) |> Repo.insert()
  end

  def create_identifier!(attrs), do: bang!(create_identifier(attrs))

  def destroy_identifier(identifier), do: Repo.delete(identifier)
  def destroy_identifier!(identifier), do: destroy_bang!(identifier)

  def find_by_tmdb_id_for_movie(tmdb_id) do
    {:ok,
     Repo.one(
       from(i in Identifier,
         where: i.property_id == "tmdb" and i.value == ^tmdb_id and not is_nil(i.movie_id),
         limit: 1
       )
     )}
  end

  def find_by_tmdb_id_for_tv_series(tmdb_id) do
    {:ok,
     Repo.one(
       from(i in Identifier,
         where: i.property_id == "tmdb" and i.value == ^tmdb_id and not is_nil(i.tv_series_id),
         limit: 1
       )
     )}
  end

  def find_by_tmdb_collection_for_movie_series(collection_id) do
    {:ok,
     Repo.one(
       from(i in Identifier,
         where:
           i.property_id == "tmdb_collection" and i.value == ^collection_id and
             not is_nil(i.movie_series_id),
         limit: 1
       )
     )}
  end

  # ---------------------------------------------------------------------------
  # Movie
  # ---------------------------------------------------------------------------

  def list_movies, do: {:ok, Repo.all(Movie)}
  def list_movies!, do: Repo.all(Movie)

  def list_movies_for_entity(entity_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    result =
      from(m in Movie, where: m.entity_id == ^entity_id)
      |> Repo.all()
      |> maybe_preload(preloads)

    {:ok, result}
  end

  def list_movies_for_entity!(entity_id, opts \\ []),
    do: bang!(list_movies_for_entity(entity_id, opts))

  def get_movie(id) do
    case Repo.get(Movie, id) do
      nil -> {:error, :not_found}
      movie -> {:ok, movie}
    end
  end

  def get_movie!(id), do: Repo.get!(Movie, id)

  def find_or_create_movie(attrs) do
    entity_id = attrs[:entity_id] || attrs["entity_id"]
    tmdb_id = attrs[:tmdb_id] || attrs["tmdb_id"]

    case Repo.get_by(Movie, entity_id: entity_id, tmdb_id: tmdb_id) do
      nil -> Movie.create_changeset(attrs) |> Repo.insert()
      existing -> {:ok, existing}
    end
  end

  def find_or_create_movie!(attrs), do: bang!(find_or_create_movie(attrs))

  def set_movie_content_url(movie, attrs) do
    Movie.set_content_url_changeset(movie, attrs) |> Repo.update()
  end

  def set_movie_content_url!(movie, attrs), do: bang!(set_movie_content_url(movie, attrs))

  def create_movie(attrs) do
    Movie.create_changeset(attrs) |> Repo.insert()
  end

  def create_movie!(attrs), do: bang!(create_movie(attrs))

  def destroy_movie(movie), do: Repo.delete(movie)
  def destroy_movie!(movie), do: destroy_bang!(movie)

  def get_movie_with_associations(id) do
    case Repo.get(Movie, id) do
      nil -> {:error, :not_found}
      movie -> {:ok, Repo.preload(movie, @movie_full_preloads)}
    end
  end

  def get_movie_with_associations!(id) do
    Repo.get!(Movie, id) |> Repo.preload(@movie_full_preloads)
  end

  def find_or_create_movie_for_series(attrs) do
    movie_series_id = attrs[:movie_series_id] || attrs["movie_series_id"]
    tmdb_id = attrs[:tmdb_id] || attrs["tmdb_id"]

    case Repo.get_by(Movie, movie_series_id: movie_series_id, tmdb_id: tmdb_id) do
      nil -> Movie.create_changeset(attrs) |> Repo.insert()
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

  def list_extras_for_entity(entity_id) do
    {:ok, from(x in Extra, where: x.entity_id == ^entity_id) |> Repo.all()}
  end

  def list_extras_for_entity!(entity_id), do: bang!(list_extras_for_entity(entity_id))

  def list_extras_for_season(season_id) do
    {:ok, from(x in Extra, where: x.season_id == ^season_id) |> Repo.all()}
  end

  def list_extras_for_season!(season_id), do: bang!(list_extras_for_season(season_id))

  def get_extra(id) do
    case Repo.get(Extra, id) do
      nil -> {:error, :not_found}
      extra -> {:ok, extra}
    end
  end

  def get_extra!(id), do: Repo.get!(Extra, id)

  def find_or_create_extra(attrs) do
    entity_id = attrs[:entity_id] || attrs["entity_id"]
    content_url = attrs[:content_url] || attrs["content_url"]

    case Repo.get_by(Extra, entity_id: entity_id, content_url: content_url) do
      nil -> Extra.create_changeset(attrs) |> Repo.insert()
      existing -> {:ok, existing}
    end
  end

  def find_or_create_extra!(attrs), do: bang!(find_or_create_extra(attrs))

  def create_extra(attrs) do
    Extra.create_changeset(attrs) |> Repo.insert()
  end

  def create_extra!(attrs), do: bang!(create_extra(attrs))

  def destroy_extra(extra), do: Repo.delete(extra)
  def destroy_extra!(extra), do: destroy_bang!(extra)

  # ---------------------------------------------------------------------------
  # Season
  # ---------------------------------------------------------------------------

  def list_seasons, do: {:ok, Repo.all(Season)}
  def list_seasons!, do: Repo.all(Season)

  def list_seasons_for_entity(entity_id) do
    {:ok, from(s in Season, where: s.entity_id == ^entity_id) |> Repo.all()}
  end

  def list_seasons_for_entity!(entity_id), do: bang!(list_seasons_for_entity(entity_id))

  def get_season(id) do
    case Repo.get(Season, id) do
      nil -> {:error, :not_found}
      season -> {:ok, season}
    end
  end

  def get_season!(id), do: Repo.get!(Season, id)

  def find_or_create_season(attrs) do
    entity_id = attrs[:entity_id] || attrs["entity_id"]
    season_number = attrs[:season_number] || attrs["season_number"]

    existing =
      if entity_id && season_number do
        Repo.get_by(Season, entity_id: entity_id, season_number: season_number)
      end

    case existing do
      nil -> Season.create_changeset(attrs) |> Repo.insert()
      record -> {:ok, record}
    end
  end

  def find_or_create_season!(attrs), do: bang!(find_or_create_season(attrs))

  def create_season(attrs) do
    Season.create_changeset(attrs) |> Repo.insert()
  end

  def create_season!(attrs), do: bang!(create_season(attrs))

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
      nil -> Season.create_changeset(attrs) |> Repo.insert()
      record -> {:ok, record}
    end
  end

  def list_seasons_for_tv_series(tv_series_id) do
    {:ok, from(s in Season, where: s.tv_series_id == ^tv_series_id) |> Repo.all()}
  end

  # ---------------------------------------------------------------------------
  # Episode
  # ---------------------------------------------------------------------------

  def list_episodes, do: {:ok, Repo.all(Episode)}
  def list_episodes!, do: Repo.all(Episode)

  def list_episodes_for_season(season_id, opts \\ []) do
    preloads = Keyword.get(opts, :load, [])

    result =
      from(e in Episode, where: e.season_id == ^season_id)
      |> Repo.all()
      |> maybe_preload(preloads)

    {:ok, result}
  end

  def list_episodes_for_season!(season_id, opts \\ []) do
    bang!(list_episodes_for_season(season_id, opts))
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
      nil -> Episode.create_changeset(attrs) |> Repo.insert()
      existing -> {:ok, existing}
    end
  end

  def find_or_create_episode!(attrs), do: bang!(find_or_create_episode(attrs))

  def set_episode_content_url(episode, attrs) do
    Episode.set_content_url_changeset(episode, attrs) |> Repo.update()
  end

  def set_episode_content_url!(episode, attrs) do
    bang!(set_episode_content_url(episode, attrs))
  end

  def create_episode(attrs) do
    Episode.create_changeset(attrs) |> Repo.insert()
  end

  def create_episode!(attrs), do: bang!(create_episode(attrs))

  def destroy_episode(episode), do: Repo.delete(episode)
  def destroy_episode!(episode), do: destroy_bang!(episode)

  # ---------------------------------------------------------------------------
  # WatchProgress
  # ---------------------------------------------------------------------------

  def list_watch_progress, do: {:ok, Repo.all(WatchProgress)}
  def list_watch_progress!, do: Repo.all(WatchProgress)

  def list_watch_progress_for_entity(entity_id) do
    query =
      from(wp in WatchProgress,
        where: wp.entity_id == ^entity_id,
        order_by: [asc: wp.season_number, asc: wp.episode_number]
      )

    {:ok, Repo.all(query)}
  end

  def list_watch_progress_for_entity!(entity_id) do
    bang!(list_watch_progress_for_entity(entity_id))
  end

  def list_recently_watched(limit) do
    query =
      from(wp in WatchProgress,
        where: not is_nil(wp.last_watched_at),
        order_by: [desc: wp.last_watched_at],
        limit: ^limit,
        preload: [:entity]
      )

    {:ok, Repo.all(query)}
  end

  def list_recently_watched!(limit), do: bang!(list_recently_watched(limit))

  def find_or_create_watch_progress(attrs) do
    entity_id = attrs[:entity_id] || attrs["entity_id"]
    season_number = attrs[:season_number] || attrs["season_number"] || 0
    episode_number = attrs[:episode_number] || attrs["episode_number"] || 0

    case Repo.get_by(WatchProgress,
           entity_id: entity_id,
           season_number: season_number,
           episode_number: episode_number
         ) do
      nil ->
        WatchProgress.upsert_changeset(attrs) |> Repo.insert()

      existing ->
        WatchProgress.upsert_changeset(existing, attrs) |> Repo.update()
    end
  end

  def find_or_create_watch_progress!(attrs), do: bang!(find_or_create_watch_progress(attrs))

  def mark_watch_completed(progress) do
    WatchProgress.mark_completed_changeset(progress) |> Repo.update()
  end

  def mark_watch_completed!(progress), do: bang!(mark_watch_completed(progress))

  def mark_watch_incomplete(progress) do
    WatchProgress.mark_incomplete_changeset(progress) |> Repo.update()
  end

  def mark_watch_incomplete!(progress), do: bang!(mark_watch_incomplete(progress))

  def destroy_watch_progress(progress), do: Repo.delete(progress)
  def destroy_watch_progress!(progress), do: destroy_bang!(progress)

  def find_or_create_watch_progress_for_movie(attrs) do
    movie_id = attrs[:movie_id] || attrs["movie_id"]

    case Repo.get_by(WatchProgress, movie_id: movie_id) do
      nil -> WatchProgress.upsert_changeset(attrs) |> Repo.insert()
      existing -> WatchProgress.upsert_changeset(existing, attrs) |> Repo.update()
    end
  end

  def find_or_create_watch_progress_for_episode(attrs) do
    episode_id = attrs[:episode_id] || attrs["episode_id"]

    case Repo.get_by(WatchProgress, episode_id: episode_id) do
      nil -> WatchProgress.upsert_changeset(attrs) |> Repo.insert()
      existing -> WatchProgress.upsert_changeset(existing, attrs) |> Repo.update()
    end
  end

  def find_or_create_watch_progress_for_video_object(attrs) do
    video_object_id = attrs[:video_object_id] || attrs["video_object_id"]

    case Repo.get_by(WatchProgress, video_object_id: video_object_id) do
      nil -> WatchProgress.upsert_changeset(attrs) |> Repo.insert()
      existing -> WatchProgress.upsert_changeset(existing, attrs) |> Repo.update()
    end
  end

  # ---------------------------------------------------------------------------
  # ExtraProgress
  # ---------------------------------------------------------------------------

  def list_extra_progress_for_entity(entity_id) do
    {:ok, from(ep in ExtraProgress, where: ep.entity_id == ^entity_id) |> Repo.all()}
  end

  def list_extra_progress_for_entity!(entity_id) do
    bang!(list_extra_progress_for_entity(entity_id))
  end

  def get_extra_progress_by_extra(extra_id) do
    {:ok, Repo.get_by(ExtraProgress, extra_id: extra_id)}
  end

  def find_or_create_extra_progress(attrs) do
    extra_id = attrs[:extra_id] || attrs["extra_id"]

    case Repo.get_by(ExtraProgress, extra_id: extra_id) do
      nil ->
        ExtraProgress.upsert_changeset(attrs) |> Repo.insert()

      existing ->
        ExtraProgress.upsert_changeset(existing, attrs) |> Repo.update()
    end
  end

  def find_or_create_extra_progress!(attrs), do: bang!(find_or_create_extra_progress(attrs))

  def mark_extra_completed(progress) do
    ExtraProgress.mark_completed_changeset(progress) |> Repo.update()
  end

  def mark_extra_completed!(progress), do: bang!(mark_extra_completed(progress))

  def mark_extra_incomplete(progress) do
    ExtraProgress.mark_incomplete_changeset(progress) |> Repo.update()
  end

  def mark_extra_incomplete!(progress), do: bang!(mark_extra_incomplete(progress))

  def destroy_extra_progress(progress), do: Repo.delete(progress)
  def destroy_extra_progress!(progress), do: destroy_bang!(progress)

  # ---------------------------------------------------------------------------
  # ChangeEntry
  # ---------------------------------------------------------------------------

  def create_change_entry(attrs) do
    ChangeEntry.create_changeset(attrs) |> Repo.insert()
  end

  def create_change_entry!(attrs), do: bang!(create_change_entry(attrs))

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

  def list_recent_changes!(limit, since), do: bang!(list_recent_changes(limit, since))

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc """
  Broadcasts `{:entities_changed, entity_ids}` to the `"library:updates"` PubSub topic.
  """
  defdelegate broadcast_entities_changed(entity_ids), to: MediaCentaur.Library.Helpers

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp bang!({:ok, result}), do: result

  defp bang!({:error, %Ecto.Changeset{} = changeset}) do
    raise Ecto.InvalidChangesetError, changeset: changeset, action: changeset.action
  end

  defp bang!({:error, reason}), do: raise("operation failed: #{inspect(reason)}")

  defp destroy_bang!(record) do
    bang!(Repo.delete(record))
    :ok
  end

  defp maybe_preload(records, []), do: records
  defp maybe_preload(records, preloads), do: Repo.preload(records, preloads)
end
