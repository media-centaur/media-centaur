defmodule MediaCentaur.Library.Ingress do
  @moduledoc """
  Library's inbound API for the pipeline. Consumes pre-built metadata
  and staged images to create or update all library records — without
  any TMDB calls.

  Returns `{:ok, entity, status, pending_images}` where status is:
  - `:new` — entity was just created
  - `:new_child` — entity existed (movie series), new child movie added
  - `:existing` — entity already existed, linked file/extra/episode

  `pending_images` is a list of image maps to be queued for download
  by the image pipeline. Image records are NOT created here — they are
  created by `Library.Inbound` after successful download.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.{ChangeLog, Entity}
  alias MediaCentaur.Pipeline.ImageProcessor
  alias MediaCentaur.Pipeline.Payload

  @spec ingest(Payload.t()) ::
          {:ok, Entity.t(), :new | :new_child | :existing, list()} | {:error, term()}
  def ingest(%Payload{metadata: metadata}) do
    case find_existing_entity(metadata.identifier) do
      {:ok, entity} ->
        Log.info(:library, "found existing entity — #{Format.short_id(entity.id)}")
        link_to_existing(entity, metadata)

      :not_found ->
        Log.info(:library, "creating new entity")
        create_new(metadata)
    end
  end

  # ---------------------------------------------------------------------------
  # Find existing entity by identifier
  # ---------------------------------------------------------------------------

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

  defp create_new(metadata) do
    entity_attrs = strip_content_url_if_extra(metadata.entity_attrs, metadata)

    with {:ok, entity} <- Library.create_entity(entity_attrs),
         :ok <- create_identifier_with_race_retry(entity, metadata.identifier) do
      entity_images = collect_images(entity.id, "entity", metadata.images)

      case create_children(entity, metadata) do
        {:ok, child_images} ->
          ChangeLog.record_addition(entity)

          Log.info(
            :library,
            "created #{metadata.entity_type} entity — #{Format.short_id(entity.id)}"
          )

          {:ok, entity, :new, entity_images ++ child_images}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:race_lost, winner_entity_id} ->
        Log.info(:library, "race lost — using winner #{Format.short_id(winner_entity_id)}")
        winner = Library.get_entity!(winner_entity_id)
        link_to_existing(winner, metadata)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Creates type-specific child records (season/episode, child movie, extra).
  # Order matters: season before extra (extra may link to the season).
  # Returns {:ok, pending_images} | {:error, reason}
  defp create_children(entity, metadata) do
    with {:ok, season_images} <- maybe_create_season(entity, metadata),
         {:ok, movie_images} <- maybe_create_child_movie(entity, metadata),
         :ok <- maybe_create_extra(entity, metadata) do
      {:ok, season_images ++ movie_images}
    end
  end

  defp maybe_create_season(_entity, %{season: nil}), do: {:ok, []}

  defp maybe_create_season(entity, %{season: season}) do
    create_season_and_episode(entity, season)
  end

  defp maybe_create_child_movie(_entity, %{child_movie: nil}), do: {:ok, []}

  defp maybe_create_child_movie(entity, %{child_movie: child_movie} = metadata) do
    child_movie = strip_child_content_url_if_extra(child_movie, metadata)

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
  defp link_to_existing(entity, %{extra: %{} = extra} = metadata) do
    season_images =
      if metadata.season do
        case create_season_and_episode(entity, metadata.season) do
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
  defp link_to_existing(entity, %{entity_type: :tv_series} = metadata) do
    if metadata.season do
      case create_season_and_episode(entity, metadata.season) do
        {:ok, images} -> {:ok, entity, :existing, images}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Movie series — ensure child movie -> :new_child
  defp link_to_existing(%{type: :movie_series} = entity, metadata) do
    if metadata.child_movie do
      with {:ok, _movie, images} <- create_child_movie(entity, metadata.child_movie),
           :ok <- create_child_movie_identifier(entity, metadata.child_movie) do
        {:ok, entity, :new_child, images}
      end
    else
      {:ok, entity, :existing, []}
    end
  end

  # Standalone movie — set content_url if nil
  defp link_to_existing(entity, metadata) do
    content_url = metadata.entity_attrs[:content_url]

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
        extension: ImageProcessor.output_extension(image.role)
      }
    end)
  end

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
  # Extra content_url stripping
  # ---------------------------------------------------------------------------

  # For extras, the file_path in metadata belongs to the extra, not the entity.
  # Strip content_url from entity and child records so they don't get the extra's path.
  defp strip_content_url_if_extra(entity_attrs, %{extra: extra}) when not is_nil(extra) do
    Map.delete(entity_attrs, :content_url)
  end

  defp strip_content_url_if_extra(entity_attrs, _metadata), do: entity_attrs

  defp strip_child_content_url_if_extra(child_movie, %{extra: extra}) when not is_nil(extra) do
    %{child_movie | attrs: Map.delete(child_movie.attrs, :content_url)}
  end

  defp strip_child_content_url_if_extra(child_movie, _metadata), do: child_movie

  # Set content_url when the upsert returned an existing record without one
  defp ensure_content_url(record, attrs, set_fn) do
    if is_nil(record.content_url) && attrs[:content_url] do
      set_fn.(record, %{content_url: attrs[:content_url]})
    end
  end
end
