defmodule MediaCentaur.Library.Inbound do
  @moduledoc """
  Subscribes to `"pipeline:publish"` and `"library:commands"` and handles
  inbound events for the Library context.

  Handles three event types:

  - `{:entity_published, event}` — creates/links Entity, children, Identifier,
    WatchedFile, queues images for download, and broadcasts `:entities_changed`
  - `{:image_ready, attrs}` — upserts a Library.Image after successful download
  - `{:rematch_requested, entity_id}` — destroys an entity and its WatchedFiles,
    then sends the file list to `"review:intake"` for re-review
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{ChangeLog, Entity, EntityCascade, Helpers}
  alias MediaCentaur.Library.WatchedFile
  alias MediaCentaur.Pipeline.ImageQueue

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.pipeline_publish())
    Phoenix.PubSub.subscribe(MediaCentaur.PubSub, MediaCentaur.Topics.library_commands())
    {:ok, %{}}
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests a published entity event into the library.

  Creates or links the Entity, children, Identifier, and WatchedFile.
  Queues images for download and broadcasts `:entities_changed`.

  The event is a plain map with keys: `entity_type`, `entity_attrs`,
  `identifier`, `images`, `season`, `child_movie`, `extra`, `file_path`,
  `watch_dir`.

  Returns `{:ok, entity, status, pending_images}` or `{:error, reason}`.
  Status is `:new`, `:new_child`, or `:existing`.
  """
  @spec ingest(map()) ::
          {:ok, Entity.t(), :new | :new_child | :existing, list()} | {:error, term()}
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
      %{role: role, content_url: content_url, extension: extension}
      |> put_owner_fk(owner_type, owner_id)

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
    with {:ok, _entity} <- Library.get_entity_with_associations(entity_id),
         files when files != [] <- Library.list_watched_files_for_entity!(entity_id) do
      file_list = Enum.map(files, &%{file_path: &1.file_path, watch_dir: &1.watch_dir})

      EntityCascade.bulk_destroy(files, WatchedFile)
      EntityCascade.destroy!(entity_id)

      Helpers.broadcast_entities_changed([entity_id])

      Phoenix.PubSub.broadcast(
        MediaCentaur.PubSub,
        MediaCentaur.Topics.review_intake(),
        {:files_for_review, file_list}
      )

      Log.info(
        :library,
        "rematch — destroyed #{Format.short_id(entity_id)}, sent #{length(file_list)} files to review"
      )
    else
      {:error, :not_found} ->
        Log.warning(:library, "rematch — entity #{Format.short_id(entity_id)} not found")

      [] ->
        Log.warning(
          :library,
          "rematch — entity #{Format.short_id(entity_id)} has no watched files"
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

  defp find_existing_entity(%{property_id: "tmdb_collection", value: value}) do
    case Library.find_by_tmdb_collection(value) do
      {:ok, %{entity: entity}} -> {:ok, entity}
      _ -> :not_found
    end
  end

  defp find_existing_entity(%{property_id: _property_id, value: value}) do
    case Library.find_by_tmdb_id(value) do
      {:ok, %{entity: entity}} -> {:ok, entity}
      _ -> :not_found
    end
  end

  # ---------------------------------------------------------------------------
  # Create new entity
  # ---------------------------------------------------------------------------

  defp create_new(event) do
    entity_attrs = strip_content_url_if_extra(event.entity_attrs, event)

    with {:ok, entity} <- Library.create_entity(entity_attrs),
         :ok <- create_identifier_with_race_retry(entity, event.identifier) do
      entity_images = collect_images(entity.id, "entity", event.images)

      case create_children(entity, event) do
        {:ok, child_images} ->
          ChangeLog.record_addition(entity)
          {:ok, entity, :new, entity_images ++ child_images}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:race_lost, winner_entity_id} ->
        Log.info(:library, "race lost — using winner #{Format.short_id(winner_entity_id)}")
        winner = Library.get_entity!(winner_entity_id)
        link_to_existing(winner, event)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_children(entity, event) do
    with {:ok, season_images} <- maybe_create_season(entity, event),
         {:ok, movie_images} <- maybe_create_child_movie(entity, event),
         :ok <- maybe_create_extra(entity, event) do
      {:ok, season_images ++ movie_images}
    end
  end

  defp maybe_create_season(_entity, %{season: nil}), do: {:ok, []}

  defp maybe_create_season(entity, %{season: season}) do
    create_season_and_episode(entity, season)
  end

  defp maybe_create_child_movie(_entity, %{child_movie: nil}), do: {:ok, []}

  defp maybe_create_child_movie(entity, %{child_movie: child_movie} = event) do
    child_movie = strip_child_content_url_if_extra(child_movie, event)

    with {:ok, _movie, images} <- create_child_movie(entity, child_movie),
         :ok <- create_child_movie_identifier(entity, child_movie) do
      {:ok, images}
    end
  end

  defp maybe_create_extra(_entity, %{extra: nil}), do: :ok
  defp maybe_create_extra(entity, %{extra: extra}), do: create_extra(entity, extra)

  # ---------------------------------------------------------------------------
  # Link to existing entity
  # ---------------------------------------------------------------------------

  # Extra on existing entity — always handled first (regardless of entity type)
  defp link_to_existing(entity, %{extra: %{} = extra} = event) do
    season_images =
      if event.season do
        case create_season_and_episode(entity, event.season) do
          {:ok, images} -> images
          {:error, _} -> []
        end
      else
        []
      end

    with :ok <- create_extra(entity, extra) do
      {:ok, entity, :existing, season_images}
    end
  end

  # TV series — ensure season + episode
  defp link_to_existing(entity, %{entity_type: :tv_series} = event) do
    if event.season do
      case create_season_and_episode(entity, event.season) do
        {:ok, images} -> {:ok, entity, :existing, images}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Movie series — ensure child movie -> :new_child
  defp link_to_existing(%{type: :movie_series} = entity, event) do
    if event.child_movie do
      with {:ok, _movie, images} <- create_child_movie(entity, event.child_movie),
           :ok <- create_child_movie_identifier(entity, event.child_movie) do
        {:ok, entity, :new_child, images}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Standalone movie — set content_url if nil
  defp link_to_existing(entity, event) do
    content_url = event.entity_attrs[:content_url]

    if is_nil(entity.content_url) && content_url do
      case Library.set_entity_content_url(entity, %{content_url: content_url}) do
        {:ok, updated} -> {:ok, updated, :existing, []}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Season + Episode
  # ---------------------------------------------------------------------------

  defp create_season_and_episode(entity, season_data) do
    season_attrs = %{
      season_number: season_data.season_number,
      name: season_data.name,
      number_of_episodes: season_data.number_of_episodes,
      entity_id: entity.id
    }

    with {:ok, season} <- Library.find_or_create_season(season_attrs) do
      Log.info(
        :library,
        "created season S#{season_data.season_number} — entity #{Format.short_id(entity.id)}"
      )

      if season_data[:episode] do
        create_episode(season, season_data.episode)
      else
        {:ok, []}
      end
    end
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

  defp create_child_movie(entity, child_movie_data) do
    movie_attrs = Map.put(child_movie_data.attrs, :entity_id, entity.id)

    case Library.find_or_create_movie(movie_attrs) do
      {:ok, movie} ->
        ensure_content_url(movie, movie_attrs, &Library.set_movie_content_url/2)
        images = collect_images(movie.id, "movie", child_movie_data[:images] || [])
        {:ok, movie, images}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_child_movie_identifier(_entity, %{identifier: nil}), do: :ok

  defp create_child_movie_identifier(entity, %{identifier: identifier}) do
    attrs = %{
      property_id: identifier.property_id,
      value: identifier.value,
      entity_id: entity.id
    }

    case Library.find_or_create_identifier(attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Extra
  # ---------------------------------------------------------------------------

  defp create_extra(entity, extra_data) do
    season =
      if extra_data.season_number do
        season_attrs = %{
          season_number: extra_data.season_number,
          name: "Season #{extra_data.season_number}",
          number_of_episodes: 0,
          entity_id: entity.id
        }

        case Library.find_or_create_season(season_attrs) do
          {:ok, season} -> season
          _ -> nil
        end
      end

    extra_attrs = %{
      name: extra_data.name,
      content_url: extra_data.content_url,
      position: 0,
      entity_id: entity.id,
      season_id: if(season, do: season.id)
    }

    case Library.find_or_create_extra(extra_attrs) do
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
  # Identifier with race-loss recovery
  # ---------------------------------------------------------------------------

  defp create_identifier_with_race_retry(entity, identifier) do
    attrs = %{
      property_id: identifier.property_id,
      value: identifier.value,
      entity_id: entity.id
    }

    case Library.find_or_create_identifier(attrs) do
      {:ok, created_identifier} ->
        if created_identifier.entity_id == entity.id do
          :ok
        else
          Library.destroy_entity!(entity)
          {:race_lost, created_identifier.entity_id}
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
    Library.link_file!(%{
      file_path: event.file_path,
      watch_dir: event.watch_dir,
      entity_id: entity.id
    })
  end

  defp queue_images(_entity, [], _event), do: :ok

  defp queue_images(entity, pending_images, event) do
    Enum.each(pending_images, fn image ->
      ImageQueue.create(%{
        owner_id: image.owner_id,
        owner_type: image.owner_type,
        role: image.role,
        source_url: image.source_url,
        entity_id: entity.id,
        watch_dir: event.watch_dir
      })
    end)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.pipeline_images(),
      {:images_pending, %{entity_id: entity.id, watch_dir: event.watch_dir}}
    )
  end

  # ---------------------------------------------------------------------------
  # Image record helpers (for :image_ready)
  # ---------------------------------------------------------------------------

  defp put_owner_fk(attrs, "entity", owner_id), do: Map.put(attrs, :entity_id, owner_id)
  defp put_owner_fk(attrs, "movie", owner_id), do: Map.put(attrs, :movie_id, owner_id)
  defp put_owner_fk(attrs, "episode", owner_id), do: Map.put(attrs, :episode_id, owner_id)

  defp conflict_target_for("entity"), do: [:entity_id, :role]
  defp conflict_target_for("movie"), do: [:movie_id, :role]
  defp conflict_target_for("episode"), do: [:episode_id, :role]
end
