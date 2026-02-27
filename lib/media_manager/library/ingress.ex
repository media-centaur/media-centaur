defmodule MediaManager.Library.Ingress do
  @moduledoc """
  Library's inbound API for the pipeline. Consumes pre-built metadata
  and staged images to create or update all library records — without
  any TMDB calls.

  Returns `{:ok, entity, status}` where status is:
  - `:new` — entity was just created
  - `:new_child` — entity existed (movie series), new child movie added
  - `:existing` — entity already existed, linked file/extra/episode
  """
  require MediaManager.Log, as: Log

  alias MediaManager.Library.{Entity, Extra, Image, Identifier, Movie, Season, Episode}
  alias MediaManager.Pipeline.Payload

  @spec ingest(Payload.t()) ::
          {:ok, Entity.t(), :new | :new_child | :existing} | {:error, term()}
  def ingest(%Payload{metadata: metadata, staged_images: staged_images}) do
    staged_images = staged_images || []

    case find_existing_entity(metadata.identifier) do
      {:ok, entity} ->
        Log.info(:library, "found existing entity #{entity.id}")
        link_to_existing(entity, metadata, staged_images)

      :not_found ->
        Log.info(:library, "no existing entity, creating new")
        create_new(metadata, staged_images)
    end
  end

  # ---------------------------------------------------------------------------
  # Find existing entity by identifier
  # ---------------------------------------------------------------------------

  defp find_existing_entity(%{property_id: "tmdb_collection", value: value}) do
    query = Ash.Query.for_read(Identifier, :find_by_tmdb_collection, %{collection_id: value})

    case Ash.read(query) do
      {:ok, [%{entity: entity}]} -> {:ok, entity}
      _ -> :not_found
    end
  end

  defp find_existing_entity(%{property_id: _property_id, value: value}) do
    query = Ash.Query.for_read(Identifier, :find_by_tmdb_id, %{tmdb_id: value})

    case Ash.read(query) do
      {:ok, [%{entity: entity}]} -> {:ok, entity}
      _ -> :not_found
    end
  end

  # ---------------------------------------------------------------------------
  # Create new entity
  # ---------------------------------------------------------------------------

  defp create_new(metadata, staged_images) do
    entity_attrs = strip_content_url_if_extra(metadata.entity_attrs, metadata)

    with {:ok, entity} <- Ash.create(Entity, entity_attrs, action: :create_from_tmdb),
         :ok <- create_identifier_with_race_retry(entity, metadata.identifier),
         :ok <- create_entity_images(entity.id, metadata.images, staged_images),
         :ok <- create_children(entity, metadata, staged_images) do
      Log.info(:library, "created #{metadata.entity_type} entity #{entity.id}")
      {:ok, entity, :new}
    else
      {:race_lost, winner_entity_id} ->
        Log.info(:library, "race lost, using winner #{winner_entity_id}")
        winner = Ash.get!(Entity, winner_entity_id)
        link_to_existing(winner, metadata, staged_images)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Creates type-specific child records (season/episode, child movie, extra).
  # Order matters: season before extra (extra may link to the season).
  defp create_children(entity, metadata, staged_images) do
    with :ok <- maybe_create_season(entity, metadata, staged_images),
         :ok <- maybe_create_child_movie(entity, metadata, staged_images),
         :ok <- maybe_create_extra(entity, metadata) do
      :ok
    end
  end

  defp maybe_create_season(_entity, %{season: nil}, _staged_images), do: :ok

  defp maybe_create_season(entity, %{season: season}, staged_images) do
    create_season_and_episode(entity, season, staged_images)
  end

  defp maybe_create_child_movie(_entity, %{child_movie: nil}, _staged_images), do: :ok

  defp maybe_create_child_movie(entity, %{child_movie: child_movie} = metadata, staged_images) do
    child_movie = strip_child_content_url_if_extra(child_movie, metadata)

    with {:ok, _movie} <- create_child_movie(entity, child_movie, staged_images),
         :ok <- create_child_movie_identifier(entity, child_movie) do
      :ok
    end
  end

  defp maybe_create_extra(_entity, %{extra: nil}), do: :ok
  defp maybe_create_extra(entity, %{extra: extra}), do: create_extra(entity, extra)

  # ---------------------------------------------------------------------------
  # Link to existing entity
  # ---------------------------------------------------------------------------

  # Extra on existing entity — always handled first (regardless of entity type)
  defp link_to_existing(entity, %{extra: %{} = extra} = metadata, staged_images) do
    # For TV extras, ensure the season exists first
    if metadata.season do
      create_season_and_episode(entity, metadata.season, staged_images)
    end

    with :ok <- create_extra(entity, extra) do
      {:ok, entity, :existing}
    end
  end

  # TV series — ensure season + episode
  defp link_to_existing(entity, %{entity_type: :tv_series} = metadata, staged_images) do
    if metadata.season do
      with :ok <- create_season_and_episode(entity, metadata.season, staged_images) do
        {:ok, entity, :existing}
      end
    else
      {:ok, entity, :existing}
    end
  end

  # Movie series — ensure child movie → :new_child
  defp link_to_existing(%{type: :movie_series} = entity, metadata, staged_images) do
    if metadata.child_movie do
      with {:ok, _movie} <- create_child_movie(entity, metadata.child_movie, staged_images),
           :ok <- create_child_movie_identifier(entity, metadata.child_movie) do
        {:ok, entity, :new_child}
      end
    else
      {:ok, entity, :existing}
    end
  end

  # Standalone movie — set content_url if nil
  defp link_to_existing(entity, metadata, _staged_images) do
    content_url = metadata.entity_attrs[:content_url]

    if is_nil(entity.content_url) && content_url do
      case Ash.update(entity, %{content_url: content_url}, action: :set_content_url) do
        {:ok, updated} -> {:ok, updated, :existing}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing}
    end
  end

  # ---------------------------------------------------------------------------
  # Season + Episode
  # ---------------------------------------------------------------------------

  defp create_season_and_episode(entity, season_data, staged_images) do
    season_attrs = %{
      season_number: season_data.season_number,
      name: season_data.name,
      number_of_episodes: season_data.number_of_episodes,
      entity_id: entity.id
    }

    with {:ok, season} <- Ash.create(Season, season_attrs, action: :find_or_create) do
      Log.info(:library, "season S#{season_data.season_number} for entity #{entity.id}")

      if season_data[:episode] do
        create_episode(season, season_data.episode, staged_images)
      else
        :ok
      end
    end
  end

  defp create_episode(season, episode_data, staged_images) do
    episode_attrs = Map.put(episode_data.attrs, :season_id, season.id)

    case Ash.create(Episode, episode_attrs, action: :find_or_create) do
      {:ok, episode} ->
        # Set content_url if the upsert returned an existing record without it
        if is_nil(episode.content_url) && episode_attrs[:content_url] do
          Ash.update(episode, %{content_url: episode_attrs[:content_url]},
            action: :set_content_url
          )
        end

        create_episode_images(episode.id, episode_data[:images] || [], staged_images)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Child Movie (for collections)
  # ---------------------------------------------------------------------------

  defp create_child_movie(entity, child_movie_data, staged_images) do
    movie_attrs = Map.put(child_movie_data.attrs, :entity_id, entity.id)

    case Ash.create(Movie, movie_attrs, action: :find_or_create) do
      {:ok, movie} ->
        # Set content_url if the upsert returned an existing record without it
        if is_nil(movie.content_url) && movie_attrs[:content_url] do
          Ash.update(movie, %{content_url: movie_attrs[:content_url]}, action: :set_content_url)
        end

        create_movie_images(movie.id, child_movie_data[:images] || [], staged_images)
        {:ok, movie}

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

    case Ash.create(Identifier, attrs, action: :find_or_create) do
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

        case Ash.create(Season, season_attrs, action: :find_or_create) do
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

    case Ash.create(Extra, extra_attrs, action: :find_or_create) do
      {:ok, _extra} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Images — create records and move staged files
  # ---------------------------------------------------------------------------

  defp create_entity_images(_entity_id, [], _staged_images), do: :ok

  defp create_entity_images(entity_id, images, staged_images) do
    images_dir = images_dir()

    image_attrs =
      Enum.map(images, fn image ->
        content_url = move_staged_image(entity_id, image, "entity", staged_images, images_dir)

        %{
          role: image.role,
          url: image.url,
          extension: image.extension,
          entity_id: entity_id,
          content_url: content_url
        }
      end)

    bulk_create_images(image_attrs, :find_or_create)
  end

  defp create_movie_images(_movie_id, [], _staged_images), do: :ok

  defp create_movie_images(movie_id, images, staged_images) do
    images_dir = images_dir()

    image_attrs =
      Enum.map(images, fn image ->
        content_url = move_staged_image(movie_id, image, "child_movie", staged_images, images_dir)

        %{
          role: image.role,
          url: image.url,
          extension: image.extension,
          movie_id: movie_id,
          content_url: content_url
        }
      end)

    bulk_create_images(image_attrs, :find_or_create_for_movie)
  end

  defp create_episode_images(_episode_id, [], _staged_images), do: :ok

  defp create_episode_images(episode_id, images, staged_images) do
    images_dir = images_dir()

    image_attrs =
      Enum.map(images, fn image ->
        content_url = move_staged_image(episode_id, image, "episode", staged_images, images_dir)

        %{
          role: image.role,
          url: image.url,
          extension: image.extension,
          episode_id: episode_id,
          content_url: content_url
        }
      end)

    bulk_create_images(image_attrs, :find_or_create_for_episode)
  end

  defp bulk_create_images([], _action), do: :ok

  defp bulk_create_images(image_attrs, action) do
    result = Ash.bulk_create(image_attrs, Image, action, return_errors?: true)

    if result.error_count > 0 do
      {:error, result.errors}
    else
      :ok
    end
  end

  defp move_staged_image(owner_id, image, owner_tag, staged_images, images_dir) do
    staged =
      Enum.find(staged_images, fn s ->
        s.owner == owner_tag && s.role == image.role
      end)

    if staged && images_dir do
      extension = image[:extension] || "jpg"
      relative_path = "#{owner_id}/#{image.role}.#{extension}"
      absolute_path = Path.join(images_dir, relative_path)

      File.mkdir_p!(Path.dirname(absolute_path))

      case File.rename(staged.local_path, absolute_path) do
        :ok ->
          relative_path

        {:error, :exdev} ->
          # Cross-device move (staging on different filesystem than images dir)
          File.cp!(staged.local_path, absolute_path)
          File.rm(staged.local_path)
          relative_path

        {:error, reason} ->
          Log.info(:library, "failed to move staged image: #{inspect(reason)}")
          nil
      end
    end
  end

  defp images_dir do
    MediaManager.Config.get(:media_images_dir)
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

    case Ash.create(Identifier, attrs, action: :find_or_create) do
      {:ok, created_identifier} ->
        if created_identifier.entity_id == entity.id do
          :ok
        else
          Ash.destroy!(entity)
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
end
