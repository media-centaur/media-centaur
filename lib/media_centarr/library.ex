defmodule MediaCentarr.Library do
  use Boundary,
    deps: [],
    exports: [
      Browser,
      EntityShape,
      Episode,
      EpisodeList,
      ExternalId,
      FileEventHandler,
      Movie,
      MovieList,
      MovieSeries,
      ProgressSummary,
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

  def tv_series_full_preloads, do: @tv_series_full_preloads
  def movie_series_full_preloads, do: @movie_series_full_preloads
  def movie_full_preloads, do: @movie_full_preloads
  def video_object_full_preloads, do: @video_object_full_preloads

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

  def create_tv_series!(attrs), do: bang!(create_tv_series(attrs))

  def update_tv_series(tv_series, attrs) do
    Repo.update(TVSeries.update_changeset(tv_series, attrs))
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
    Repo.preload(Repo.get!(MovieSeries, id), @movie_series_full_preloads)
  end

  def create_movie_series(attrs) do
    Repo.insert(MovieSeries.create_changeset(attrs))
  end

  def create_movie_series!(attrs), do: bang!(create_movie_series(attrs))

  def update_movie_series(movie_series, attrs) do
    Repo.update(MovieSeries.update_changeset(movie_series, attrs))
  end

  def update_movie_series!(movie_series, attrs), do: bang!(update_movie_series(movie_series, attrs))

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

  def create_video_object!(attrs), do: bang!(create_video_object(attrs))

  def update_video_object(video_object, attrs) do
    Repo.update(VideoObject.update_changeset(video_object, attrs))
  end

  def update_video_object!(video_object, attrs), do: bang!(update_video_object(video_object, attrs))

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

  def link_file!(attrs), do: bang!(link_file(attrs))

  def list_files_by_paths(file_paths) do
    {:ok, Repo.all(from(w in WatchedFile, where: w.file_path in ^file_paths))}
  end

  def list_files_by_paths!(file_paths), do: bang!(list_files_by_paths(file_paths))

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

  # ---------------------------------------------------------------------------
  # Image
  # ---------------------------------------------------------------------------

  def list_all_images, do: Repo.all(Image)

  def create_image(attrs) do
    Repo.insert(Image.create_changeset(attrs))
  end

  def create_image!(attrs), do: bang!(create_image(attrs))

  def upsert_image(attrs, conflict_target) do
    Repo.insert(Image.create_changeset(attrs),
      on_conflict: {:replace, [:content_url, :extension, :updated_at]},
      conflict_target: conflict_target
    )
  end

  def update_image(image, attrs) do
    Repo.update(Image.update_changeset(image, attrs))
  end

  def update_image!(image, attrs), do: bang!(update_image(image, attrs))

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

  def find_or_create_external_id!(attrs), do: bang!(find_or_create_external_id(attrs))

  def create_external_id(attrs) do
    Repo.insert(ExternalId.create_changeset(attrs))
  end

  def create_external_id!(attrs), do: bang!(create_external_id(attrs))

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

  def set_movie_content_url!(movie, attrs), do: bang!(set_movie_content_url(movie, attrs))

  def create_movie(attrs) do
    Repo.insert(Movie.create_changeset(attrs))
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

  def list_extras_for_season!(season_id), do: bang!(list_extras_for_season(season_id))

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

  def create_extra!(attrs), do: bang!(create_extra(attrs))

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
      nil -> Repo.insert(Episode.create_changeset(attrs))
      existing -> {:ok, existing}
    end
  end

  def find_or_create_episode!(attrs), do: bang!(find_or_create_episode(attrs))

  def set_episode_content_url(episode, attrs) do
    Repo.update(Episode.set_content_url_changeset(episode, attrs))
  end

  def set_episode_content_url!(episode, attrs) do
    bang!(set_episode_content_url(episode, attrs))
  end

  def create_episode(attrs) do
    Repo.insert(Episode.create_changeset(attrs))
  end

  def create_episode!(attrs), do: bang!(create_episode(attrs))

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

  def mark_watch_completed!(progress), do: bang!(mark_watch_completed(progress))

  def mark_watch_incomplete(progress) do
    Repo.update(WatchProgress.mark_incomplete_changeset(progress))
  end

  def mark_watch_incomplete!(progress), do: bang!(mark_watch_incomplete(progress))

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

  def find_or_create_extra_progress!(attrs), do: bang!(find_or_create_extra_progress(attrs))

  def mark_extra_completed(progress) do
    Repo.update(ExtraProgress.mark_completed_changeset(progress))
  end

  def mark_extra_completed!(progress), do: bang!(mark_extra_completed(progress))

  def mark_extra_incomplete(progress) do
    Repo.update(ExtraProgress.mark_incomplete_changeset(progress))
  end

  def mark_extra_incomplete!(progress), do: bang!(mark_extra_incomplete(progress))

  def destroy_extra_progress(progress), do: Repo.delete(progress)
  def destroy_extra_progress!(progress), do: destroy_bang!(progress)

  # ---------------------------------------------------------------------------
  # ChangeEntry
  # ---------------------------------------------------------------------------

  def create_change_entry(attrs) do
    Repo.insert(ChangeEntry.create_changeset(attrs))
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
  defdelegate broadcast_entities_changed(entity_ids), to: MediaCentarr.Library.Helpers

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
