defmodule MediaCentarr.Library.Inbound do
  @moduledoc """
  Subscribes to `"pipeline:publish"` and `"library:commands"` and handles
  inbound events for the Library context.

  Handles three event types:

  - `{:entity_published, event}` — creates a type-specific record (TVSeries,
    MovieSeries, Movie, VideoObject), children, ExternalId, WatchedFile, queues
    images for download, and broadcasts `:entities_changed`
  - `{:image_ready, attrs}` — upserts a Library.Image after successful download
  - `{:rematch_requested, entity_id}` — destroys an entity and its WatchedFiles,
    then sends the file list to `"review:intake"` for re-review

  Existing entities are resolved by joining through `library_external_ids` —
  `MediaCentarr.Library.ExternalIds` is the sole source of truth for
  TMDB / IMDB ids (Library Schema v2 Phase 1 Task 6).

  ## Race-loss recovery

  Concurrent inserts of the same TMDB id no longer surface as a column-level
  unique-constraint violation on the container (the column is gone). The
  race is now detected at the `ExternalIds.put/3` call site after a
  successful container insert: if the put fails with the
  `(source, external_id, owner_fk)` unique index, the losing process looks
  up the winning ExternalId, deletes its orphaned container, and returns
  the winner.
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Format
  alias MediaCentarr.Library
  alias MediaCentarr.Library.{ChangeLog, EntityCascade, ExternalIds, Helpers}
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

  # `ingest/1`, `process_image_ready/1`, and `handle_rematch/1` all do real
  # DB work. Running them inline blocks the mailbox during burst ingest from
  # the import Broadway pipeline. Offload to the task supervisor so the
  # GenServer can drain its mailbox; SQLite single-writer semantics serialize
  # the actual writes downstream, and `race_winner/2` already handles the
  # rare concurrent same-entity case via the unique constraint.
  @impl true
  def handle_info({:entity_published, event}, state) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn -> ingest(event) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:image_ready, attrs}, state) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn -> process_image_ready(attrs) end)
    {:noreply, state}
  end

  @impl true
  def handle_info({:rematch_requested, entity_id}, state) do
    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn -> handle_rematch(entity_id) end)
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
    case Library.find_movie_series_by_tmdb_id(value) do
      nil -> :not_found
      entity -> {:ok, entity}
    end
  end

  defp find_existing_entity(%{source: _source, external_id: value}) do
    cond do
      tv = Library.find_tv_series_by_tmdb_id(value) -> {:ok, tv}
      movie = Library.find_movie_by_tmdb_id(value) -> {:ok, movie}
      vo = Library.find_video_object_by_tmdb_id(value) -> {:ok, vo}
      true -> :not_found
    end
  end

  # ---------------------------------------------------------------------------
  # Create new type-specific record
  # ---------------------------------------------------------------------------

  defp create_new(event) do
    {entity_attrs, tmdb_id, imdb_id} = split_external_ids(event.entity_attrs)
    entity_attrs = strip_content_url_if_extra(entity_attrs, event)
    shared_id = Ecto.UUID.generate()

    case create_type_record(event.entity_type, entity_attrs, shared_id) do
      {:ok, type_record} ->
        case put_external_ids(event, type_record, tmdb_id, imdb_id) do
          {:ok, type_record} ->
            owner_type = owner_type_for(event.entity_type)
            entity_images = collect_images(type_record.id, owner_type, event.images)

            case create_children(type_record, event) do
              {:ok, child_images} ->
                ChangeLog.record_addition(type_record, event.entity_type)
                {:ok, type_record, :new, entity_images ++ child_images}

              {:error, reason} ->
                {:error, reason}
            end

          {:race_lost, winner} ->
            Log.info(:library, "race lost — using winner #{Format.short_id(winner.id)}")
            EntityCascade.destroy!(type_record.id)
            link_to_existing(winner, event)
        end

      {:error, _reason} = error ->
        error
    end
  end

  # Splits TMDB/IMDB ids out of the container attrs. The container columns
  # are gone; these ride on `library_external_ids` rows written after the
  # container insert.
  defp split_external_ids(entity_attrs) do
    tmdb_id = entity_attrs[:tmdb_id] || entity_attrs["tmdb_id"]
    imdb_id = entity_attrs[:imdb_id] || entity_attrs["imdb_id"]

    stripped = Map.drop(entity_attrs, [:tmdb_id, :imdb_id, "tmdb_id", "imdb_id"])

    {stripped, tmdb_id, imdb_id}
  end

  # Writes the TMDB / IMDB ExternalId rows for a freshly-inserted
  # container. The TMDB write is race-aware: if a concurrent ingest of
  # the same TMDB id won, our ExternalId insert hits the owner-FK-scoped
  # unique index *or* finds a winning row on another container. Look up
  # the winner and signal `:race_lost`; the caller cleans up the orphan
  # container so the loser doesn't leave a stale row behind.
  defp put_external_ids(event, type_record, tmdb_id, imdb_id) do
    case put_tmdb_id(event, type_record, tmdb_id) do
      :ok ->
        _ = ExternalIds.put(:imdb, type_record, imdb_id)
        {:ok, type_record}

      {:race_lost, winner} ->
        {:race_lost, winner}
    end
  end

  defp put_tmdb_id(_event, _type_record, nil), do: :ok

  defp put_tmdb_id(event, type_record, tmdb_id) when is_binary(tmdb_id) do
    source = tmdb_source_for(event.entity_type)

    case ExternalIds.put(source, type_record, tmdb_id) do
      {:ok, _row} ->
        :ok

      {:error, %Ecto.Changeset{}} ->
        # Either same `(source, external_id)` is already attached to this
        # container by a concurrent put (handled idempotently by `put/3`
        # itself), or it now attaches to a different winning container.
        # Resolve via cross-owner lookup.
        case find_winner(event.entity_type, tmdb_id) do
          nil ->
            Log.warning(
              :library,
              "race-loss: ExternalId conflict on (#{event.entity_type}, tmdb:#{tmdb_id}) but no owner found"
            )

            :ok

          %{id: same_id} when same_id == type_record.id ->
            :ok

          winner ->
            {:race_lost, winner}
        end
    end
  end

  defp find_winner(:tv_series, value), do: Library.find_tv_series_by_tmdb_id(value)
  defp find_winner(:movie_series, value), do: Library.find_movie_series_by_tmdb_id(value)
  defp find_winner(:movie, value), do: Library.find_movie_by_tmdb_id(value)
  defp find_winner(:video_object, value), do: Library.find_video_object_by_tmdb_id(value)

  defp tmdb_source_for(:movie_series), do: :tmdb_collection
  defp tmdb_source_for(_), do: :tmdb

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

    case create_child_movie(entity_type, entity_id, child_movie) do
      {:ok, _movie, images} -> {:ok, images}
      {:error, reason} -> {:error, reason}
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
      case create_child_movie(:movie_series, entity.id, event.child_movie) do
        {:ok, _movie, images} -> {:ok, entity, :new_child, images}
        {:error, reason} -> {:error, reason}
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
    {fk_type, fk_id} = file_owner_for(entity, event)

    attrs =
      put_type_fk(
        %{
          file_path: event.file_path,
          watch_dir: event.watch_dir
        },
        fk_type,
        fk_id
      )

    watched_file = Library.link_file!(attrs)

    # Persist detected subtitle tracks against the freshly-linked file.
    # The Subtitles context owns its own table; we hand it the FK and
    # the detector output.
    detected = MediaCentarr.Subtitles.detect(event.file_path)

    case MediaCentarr.Subtitles.replace_tracks_for_file(watched_file.id, detected) do
      {:ok, _tracks} ->
        :ok

      {:error, reason} ->
        Log.warning(
          :library,
          "subtitle persist failed for watched_file #{watched_file.id}: #{inspect(reason)}"
        )
    end

    watched_file
  end

  # A collection-child movie owns its own WatchedFile; the parent MovieSeries
  # is the entity row but not the file owner. Misattaching the file to
  # movie_series_id hides the collection from PresentableQueries
  # (which count files via wf.movie_id on child movies).
  defp file_owner_for(_entity, %{
         entity_type: :movie_series,
         child_movie: %{attrs: %{tmdb_id: child_tmdb_id}}
       })
       when is_binary(child_tmdb_id) do
    %{id: id} = Library.find_movie_by_tmdb_id(child_tmdb_id)
    {:movie, id}
  end

  defp file_owner_for(entity, event), do: {event.entity_type, entity.id}

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
