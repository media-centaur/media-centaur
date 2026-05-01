defmodule MediaCentarr.Library.Inbound do
  @moduledoc """
  Subscribes to `"pipeline:publish"` and `"library:commands"` and handles
  inbound events for the Library context.

  Handles three event types:

  - `{:entity_published, event}` — creates a type-specific record (TVSeries,
    MovieSeries, Movie, VideoObject), children, Identifier, WatchedFile, queues
    images for download, and broadcasts `:entities_changed`
  - `{:image_ready, attrs}` — upserts a Library.Image after successful download
  - `{:rematch_requested, entity_id}` — destroys an entity and its WatchedFiles,
    then sends the file list to `"review:intake"` for re-review

  Entities are created as type-specific records (TVSeries, MovieSeries, Movie,
  VideoObject). Existing entities are found by TMDB ID lookup on ExternalId records.
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Format
  alias MediaCentarr.Library
  alias MediaCentarr.Library.{ChangeLog, EntityCascade, Helpers}
  alias MediaCentarr.Library.WatchedFile

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.pipeline_publish())
    Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.library_commands())
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests a published entity event into the library.

  Creates a type-specific record (or links to an existing entity), children,
  ExternalId, and WatchedFile. Queues images for download and broadcasts
  `:entities_changed`.

  The event is a plain map with keys: `entity_type`, `entity_attrs`,
  `identifier`, `images`, `season`, `child_movie`, `extra`, `file_path`,
  `watch_dir`.

  Returns `{:ok, entity, status, pending_images}` or `{:error, reason}`.
  Status is `:new`, `:new_child`, or `:existing`.
  """
  @spec ingest(map()) ::
          {:ok, map(), :new | :new_child | :existing, list()} | {:error, term()}
  def ingest(event) do
    case create_or_link(event) do
      {:ok, entity, status, pending_images} ->
        link_file(entity, event)
        queue_images(entity, pending_images, event)
        Helpers.broadcast_entities_changed([entity.id])

        Log.info(
          :library,
          "ingested #{event.entity_type} — #{Format.short_id(entity.id)} (#{status})"
        )

        {:ok, entity, status, pending_images}

      {:error, reason} ->
        Log.warning(:library, "failed to ingest entity: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Processes an image download completion event.

  Creates or updates a `Library.Image` record with `content_url` already
  set, then broadcasts `:entities_changed`.

  Returns `:ok`.
  """
  def process_image_ready(attrs) do
    %{
      owner_id: owner_id,
      owner_type: owner_type,
      role: role,
      content_url: content_url,
      extension: extension,
      entity_id: entity_id
    } = attrs

    image_attrs =
      put_owner_fk(
        %{role: role, content_url: content_url, extension: extension},
        owner_type,
        owner_id
      )

    conflict_target = conflict_target_for(owner_type)

    case Library.upsert_image(image_attrs, conflict_target) do
      {:ok, _image} ->
        Log.info(:library, "image ready — #{role} for #{owner_id}")

      {:error, reason} ->
        Log.warning(
          :library,
          "failed to create image — #{role} for #{owner_id}: #{inspect(reason)}"
        )
    end

    Helpers.broadcast_entities_changed([entity_id])

    :ok
  end

  @doc """
  Handles a rematch request for an entity.

  Loads the entity and its WatchedFiles, collects file info, destroys
  the WatchedFiles and entity cascade, then broadcasts the file list
  to `"review:intake"` for re-review.

  Logs a warning and returns `:ok` if the entity doesn't exist or has
  no watched files — the caller (GenServer callback) doesn't act on errors.
  """
  @spec handle_rematch(String.t()) :: :ok
  def handle_rematch(entity_id) do
    files = Library.list_watched_files_by_entity_id(entity_id)

    if files == [] do
      Log.warning(
        :library,
        "rematch — entity #{Format.short_id(entity_id)} has no watched files or not found"
      )
    else
      file_list = Enum.map(files, &%{file_path: &1.file_path, watch_dir: &1.watch_dir})

      EntityCascade.bulk_destroy(files, WatchedFile)
      EntityCascade.destroy!(entity_id)

      Helpers.broadcast_entities_changed([entity_id])

      Phoenix.PubSub.broadcast(
        MediaCentarr.PubSub,
        MediaCentarr.Topics.review_intake(),
        {:files_for_review, file_list}
      )

      Log.info(
        :library,
        "rematch — destroyed #{Format.short_id(entity_id)}, sent #{length(file_list)} files to review"
      )
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:entity_published, event}, state) do
    ingest(event)
    {:noreply, state}
  end

  @impl true
  def handle_info({:image_ready, attrs}, state) do
    process_image_ready(attrs)
    {:noreply, state}
  end

  @impl true
  def handle_info({:rematch_requested, entity_id}, state) do
    handle_rematch(entity_id)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Entity creation / linking
  # ---------------------------------------------------------------------------

  defp create_or_link(event) do
    case find_existing_entity(event.identifier) do
      {:ok, entity} ->
        Log.info(:library, "found existing entity — #{Format.short_id(entity.id)}")
        link_to_existing(entity, event)

      :not_found ->
        Log.info(:library, "creating new entity")
        create_new(event)
    end
  end

  defp find_existing_entity(%{source: "tmdb_collection", external_id: value}) do
    case Library.find_by_tmdb_collection_for_movie_series(value) do
      %{movie_series_id: id} when not is_nil(id) ->
        {:ok, Library.get_movie_series!(id)}

      _ ->
        :not_found
    end
  end

  defp find_existing_entity(%{source: _source, external_id: value}) do
    case Library.find_by_tmdb_id_for_tv_series(value) do
      %{tv_series_id: id} when not is_nil(id) ->
        {:ok, Library.get_tv_series!(id)}

      _ ->
        case Library.find_by_tmdb_id_for_movie(value) do
          %{movie_id: id} when not is_nil(id) ->
            {:ok, Library.get_movie!(id)}

          _ ->
            :not_found
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Create new type-specific record
  # ---------------------------------------------------------------------------

  defp create_new(event) do
    entity_attrs = strip_content_url_if_extra(event.entity_attrs, event)
    shared_id = Ecto.UUID.generate()

    with {:ok, type_record} <- create_type_record(event.entity_type, entity_attrs, shared_id),
         :ok <- create_external_id_with_race_retry(type_record, event) do
      owner_type = owner_type_for(event.entity_type)
      entity_images = collect_images(type_record.id, owner_type, event.images)

      case create_children(type_record, event) do
        {:ok, child_images} ->
          ChangeLog.record_addition(type_record, event.entity_type)
          {:ok, type_record, :new, entity_images ++ child_images}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:race_lost, winner_entity_id} ->
        Log.info(:library, "race lost — using winner #{Format.short_id(winner_entity_id)}")
        winner = resolve_type_record!(event.entity_type, winner_entity_id)
        link_to_existing(winner, event)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_type_record(:tv_series, attrs, shared_id) do
    Library.create_tv_series(Map.put(attrs, :id, shared_id))
  end

  defp create_type_record(:movie_series, attrs, shared_id) do
    Library.create_movie_series(Map.put(attrs, :id, shared_id))
  end

  defp create_type_record(:movie, attrs, shared_id) do
    Library.create_movie(Map.put(attrs, :id, shared_id))
  end

  defp create_type_record(:video_object, attrs, shared_id) do
    Library.create_video_object(Map.put(attrs, :id, shared_id))
  end

  # Maps entity_type atom to the owner_type string used in image metadata
  defp owner_type_for(:tv_series), do: "tv_series"
  defp owner_type_for(:movie_series), do: "movie_series"
  defp owner_type_for(:movie), do: "movie"
  defp owner_type_for(:video_object), do: "video_object"

  # Maps entity_type atom to the FK key used in child records
  defp type_fk_for(:tv_series), do: :tv_series_id
  defp type_fk_for(:movie_series), do: :movie_series_id
  defp type_fk_for(:movie), do: :movie_id
  defp type_fk_for(:video_object), do: :video_object_id

  defp create_children(record, event) do
    entity_type = event.entity_type
    entity_id = record.id

    with {:ok, season_images} <- maybe_create_season(entity_type, entity_id, event),
         {:ok, movie_images} <- maybe_create_child_movie(entity_type, entity_id, event),
         :ok <- maybe_create_extra(entity_type, entity_id, event) do
      {:ok, season_images ++ movie_images}
    end
  end

  defp maybe_create_season(_entity_type, _entity_id, %{season: nil}), do: {:ok, []}

  defp maybe_create_season(entity_type, entity_id, %{season: season}) do
    create_season_and_episode(entity_type, entity_id, season)
  end

  defp maybe_create_child_movie(_entity_type, _entity_id, %{child_movie: nil}), do: {:ok, []}

  defp maybe_create_child_movie(entity_type, entity_id, %{child_movie: child_movie} = event) do
    child_movie = strip_child_content_url_if_extra(child_movie, event)

    with {:ok, _movie, images} <- create_child_movie(entity_type, entity_id, child_movie),
         :ok <- create_child_movie_identifier(entity_type, entity_id, child_movie) do
      {:ok, images}
    end
  end

  defp maybe_create_extra(_entity_type, _entity_id, %{extra: nil}), do: :ok

  defp maybe_create_extra(entity_type, entity_id, %{extra: extra}) do
    create_extra(entity_type, entity_id, extra)
  end

  # ---------------------------------------------------------------------------
  # Link to existing entity
  # ---------------------------------------------------------------------------

  defp link_to_existing(entity, event) do
    do_link_to_existing(entity, event)
  end

  # Extra on existing entity — always handled first (regardless of entity type)
  defp do_link_to_existing(entity, %{extra: %{} = extra} = event) do
    entity_type = event.entity_type

    season_images =
      if event.season do
        case create_season_and_episode(entity_type, entity.id, event.season) do
          {:ok, images} -> images
          {:error, _} -> []
        end
      else
        []
      end

    with :ok <- create_extra(entity_type, entity.id, extra) do
      {:ok, entity, :existing, season_images}
    end
  end

  # TV series — ensure season + episode
  defp do_link_to_existing(entity, %{entity_type: :tv_series} = event) do
    if event.season do
      case create_season_and_episode(:tv_series, entity.id, event.season) do
        {:ok, images} -> {:ok, entity, :existing, images}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Movie series — ensure child movie -> :new_child
  defp do_link_to_existing(entity, %{entity_type: :movie_series} = event) do
    if event.child_movie do
      with {:ok, _movie, images} <-
             create_child_movie(:movie_series, entity.id, event.child_movie),
           :ok <- create_child_movie_identifier(:movie_series, entity.id, event.child_movie) do
        {:ok, entity, :new_child, images}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Standalone movie or video object — set content_url if entity has none yet
  # AND the inbound event carries a non-nil one.
  defp do_link_to_existing(%{content_url: nil} = entity, event) do
    case event.entity_attrs[:content_url] do
      nil ->
        {:ok, entity, :existing, []}

      url ->
        case set_content_url(entity, event.entity_type, url) do
          {:ok, updated} -> {:ok, updated, :existing, []}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp do_link_to_existing(entity, _event), do: {:ok, entity, :existing, []}

  defp set_content_url(record, :movie, url) do
    Library.set_movie_content_url(record, %{content_url: url})
  end

  defp set_content_url(record, :video_object, url) do
    Library.update_video_object(record, %{content_url: url})
  end

  defp set_content_url(record, _type, _url), do: {:ok, record}

  # ---------------------------------------------------------------------------
  # Season + Episode
  # ---------------------------------------------------------------------------

  defp create_season_and_episode(entity_type, entity_id, season_data) do
    season_attrs =
      put_type_fk(
        %{
          season_number: season_data.season_number,
          name: season_data.name,
          number_of_episodes: season_data.number_of_episodes
        },
        entity_type,
        entity_id
      )

    with {:ok, season} <- find_or_create_season(entity_type, season_attrs) do
      Log.info(
        :library,
        "created season S#{season_data.season_number} — entity #{Format.short_id(entity_id)}"
      )

      if season_data[:episode] do
        create_episode(season, season_data.episode)
      else
        {:ok, []}
      end
    end
  end

  defp find_or_create_season(:tv_series, attrs) do
    Library.find_or_create_season_for_tv_series(attrs)
  end

  defp find_or_create_season(_entity_type, attrs) do
    # Non-TV-series types create seasons directly (rare case — extras with season context)
    Library.create_season(attrs)
  end

  defp create_episode(season, episode_data) do
    episode_attrs = Map.put(episode_data.attrs, :season_id, season.id)

    case Library.find_or_create_episode(episode_attrs) do
      {:ok, episode} ->
        ensure_content_url(episode, episode_attrs, &Library.set_episode_content_url/2)
        images = collect_images(episode.id, "episode", episode_data[:images] || [])
        {:ok, images}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Child Movie (for collections)
  # ---------------------------------------------------------------------------

  defp create_child_movie(entity_type, entity_id, child_movie_data) do
    movie_attrs =
      maybe_put(child_movie_data.attrs, :movie_series_id, entity_id, entity_type == :movie_series)

    result = Library.find_or_create_movie_for_series(movie_attrs)

    case result do
      {:ok, movie} ->
        ensure_content_url(movie, movie_attrs, &Library.set_movie_content_url/2)
        images = collect_images(movie.id, "movie", child_movie_data[:images] || [])
        {:ok, movie, images}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_child_movie_identifier(_entity_type, _entity_id, %{identifier: nil}), do: :ok

  defp create_child_movie_identifier(entity_type, entity_id, %{identifier: identifier}) do
    attrs =
      put_type_fk(
        %{source: identifier.source, external_id: identifier.external_id},
        entity_type,
        entity_id
      )

    case Library.find_or_create_external_id(attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Extra
  # ---------------------------------------------------------------------------

  defp create_extra(entity_type, entity_id, extra_data) do
    season =
      if extra_data.season_number do
        season_attrs =
          put_type_fk(
            %{
              season_number: extra_data.season_number,
              name: "Season #{extra_data.season_number}",
              number_of_episodes: 0
            },
            entity_type,
            entity_id
          )

        case find_or_create_season(entity_type, season_attrs) do
          {:ok, season} -> season
          _ -> nil
        end
      end

    extra_attrs =
      put_type_fk(
        %{
          name: extra_data.name,
          content_url: extra_data.content_url,
          position: 0,
          season_id: if(season, do: season.id)
        },
        entity_type,
        entity_id
      )

    type_fk = type_fk_for(entity_type)

    case Library.find_or_create_extra_by_type(extra_attrs, type_fk) do
      {:ok, _extra} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Images — collect pending image metadata (no DB inserts)
  # ---------------------------------------------------------------------------

  defp collect_images(_owner_id, _owner_type, []), do: []

  defp collect_images(owner_id, owner_type, images) do
    Enum.map(images, fn image ->
      %{
        owner_id: owner_id,
        owner_type: owner_type,
        role: image.role,
        source_url: image.url,
        extension: output_extension(image.role)
      }
    end)
  end

  defp output_extension("logo"), do: "png"
  defp output_extension(_role), do: "jpg"

  # ---------------------------------------------------------------------------
  # ExternalId with race-loss recovery
  # ---------------------------------------------------------------------------

  defp create_external_id_with_race_retry(type_record, event) do
    type_fk = type_fk_for(event.entity_type)

    attrs =
      put_type_fk(
        %{source: event.identifier.source, external_id: event.identifier.external_id},
        event.entity_type,
        type_record.id
      )

    case Library.find_or_create_external_id(attrs) do
      {:ok, created_external_id} ->
        # Check the type-specific FK to detect race loss. If the returned
        # external ID belongs to a different entity, we lost the race.
        owner_id = Map.get(created_external_id, type_fk)

        if owner_id == type_record.id do
          :ok
        else
          destroy_type_record(event.entity_type, type_record)
          {:race_lost, owner_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Content URL helpers
  # ---------------------------------------------------------------------------

  defp strip_content_url_if_extra(entity_attrs, %{extra: extra}) when not is_nil(extra) do
    Map.delete(entity_attrs, :content_url)
  end

  defp strip_content_url_if_extra(entity_attrs, _event), do: entity_attrs

  defp strip_child_content_url_if_extra(child_movie, %{extra: extra}) when not is_nil(extra) do
    %{child_movie | attrs: Map.delete(child_movie.attrs, :content_url)}
  end

  defp strip_child_content_url_if_extra(child_movie, _event), do: child_movie

  defp ensure_content_url(record, attrs, set_fn) do
    if is_nil(record.content_url) && attrs[:content_url] do
      set_fn.(record, %{content_url: attrs[:content_url]})
    end
  end

  # ---------------------------------------------------------------------------
  # Post-ingest: file linking and image queuing
  # ---------------------------------------------------------------------------

  defp link_file(entity, event) do
    attrs =
      put_type_fk(
        %{file_path: event.file_path, watch_dir: event.watch_dir},
        event.entity_type,
        entity.id
      )

    Library.link_file!(attrs)
  end

  defp queue_images(_entity, [], _event), do: :ok

  defp queue_images(entity, pending_images, event) do
    Phoenix.PubSub.broadcast(
      MediaCentarr.PubSub,
      MediaCentarr.Topics.pipeline_images(),
      {:enqueue_images, %{entity_id: entity.id, watch_dir: event.watch_dir, images: pending_images}}
    )
  end

  # ---------------------------------------------------------------------------
  # Type FK helpers
  # ---------------------------------------------------------------------------

  # Adds the type-specific FK to attrs.
  defp put_type_fk(attrs, entity_type, entity_id) do
    Map.put(attrs, type_fk_for(entity_type), entity_id)
  end

  # Loads a type-specific record by type + id (used for race-loss recovery).
  defp resolve_type_record!(:tv_series, id), do: Library.get_tv_series!(id)
  defp resolve_type_record!(:movie_series, id), do: Library.get_movie_series!(id)
  defp resolve_type_record!(:movie, id), do: Library.get_movie!(id)
  defp resolve_type_record!(:video_object, id), do: Library.get_video_object!(id)

  # Destroys a type-specific record (used for race-loss cleanup).
  defp destroy_type_record(:tv_series, record), do: Library.destroy_tv_series!(record)
  defp destroy_type_record(:movie_series, record), do: Library.destroy_movie_series!(record)
  defp destroy_type_record(:movie, record), do: Library.destroy_movie!(record)
  defp destroy_type_record(:video_object, record), do: Library.destroy_video_object!(record)

  # Conditionally puts a key-value pair into a map.
  defp maybe_put(map, _key, _value, false), do: map
  defp maybe_put(map, key, value, true), do: Map.put(map, key, value)

  # ---------------------------------------------------------------------------
  # Image record helpers (for :image_ready)
  # ---------------------------------------------------------------------------

  defp put_owner_fk(attrs, "movie", owner_id), do: Map.put(attrs, :movie_id, owner_id)
  defp put_owner_fk(attrs, "episode", owner_id), do: Map.put(attrs, :episode_id, owner_id)
  defp put_owner_fk(attrs, "tv_series", owner_id), do: Map.put(attrs, :tv_series_id, owner_id)

  defp put_owner_fk(attrs, "movie_series", owner_id), do: Map.put(attrs, :movie_series_id, owner_id)

  defp put_owner_fk(attrs, "video_object", owner_id), do: Map.put(attrs, :video_object_id, owner_id)

  defp conflict_target_for("movie"), do: [:movie_id, :role]
  defp conflict_target_for("episode"), do: [:episode_id, :role]
  defp conflict_target_for("tv_series"), do: [:tv_series_id, :role]
  defp conflict_target_for("movie_series"), do: [:movie_series_id, :role]
  defp conflict_target_for("video_object"), do: [:video_object_id, :role]
end
