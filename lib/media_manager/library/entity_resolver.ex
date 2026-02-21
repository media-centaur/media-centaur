defmodule MediaManager.Library.EntityResolver do
  @moduledoc """
  Orchestrates entity find-or-create logic for the ingestion pipeline.

  Given a TMDB ID and parsed media type, either finds an existing entity
  (by TMDB identifier) or creates a new one with full metadata, images,
  identifiers, and (for TV) season/episode records.

  Returns `{:ok, entity, :new | :existing}` or `{:error, reason}`.
  """

  alias MediaManager.TMDB.{Client, Mapper}
  alias MediaManager.Library.{Entity, Image, Identifier, Movie, Season, Episode}

  @doc """
  Resolves a TMDB ID to an entity — reusing an existing one or creating new.

  `file_context` is a map with `:file_path`, `:season_number`, `:episode_number`.
  """
  def resolve(tmdb_id, parsed_type, file_context) do
    case find_existing_entity(tmdb_id) do
      {:ok, entity} ->
        link_file_to_existing_entity(entity, parsed_type, file_context)

      :not_found ->
        create_new_entity(tmdb_id, parsed_type, file_context)
    end
  end

  # --- Find existing ---

  defp find_existing_entity(tmdb_id) do
    case Ash.read(Identifier,
           action: :find_by_tmdb_id,
           args: %{tmdb_id: to_string(tmdb_id)}
         ) do
      {:ok, [%{entity: entity}]} -> {:ok, entity}
      _ -> :not_found
    end
  end

  # --- Link file to existing entity ---

  defp link_file_to_existing_entity(entity, :tv, file_context) do
    with :ok <- ensure_episode_exists(entity, file_context) do
      {:ok, entity, :existing}
    end
  end

  defp link_file_to_existing_entity(%{type: :movie_series} = entity, _type, file_context) do
    with {:ok, _movie} <- ensure_child_movie_exists(entity, file_context) do
      {:ok, entity, :existing}
    end
  end

  defp link_file_to_existing_entity(entity, _type, file_context) do
    if is_nil(entity.content_url) do
      case Ash.update(entity, %{content_url: file_context.file_path}, action: :set_content_url) do
        {:ok, updated} -> {:ok, updated, :existing}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, entity, :existing}
    end
  end

  # --- Create new entity ---

  defp create_new_entity(tmdb_id, type, file_context) when type in [:movie, :unknown] do
    case Client.get_movie(tmdb_id) do
      {:ok, data} -> create_movie_entity(tmdb_id, data, file_context)
      {:error, _} when type == :unknown -> create_new_tv_entity(tmdb_id, file_context)
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_new_entity(tmdb_id, :tv, file_context) do
    create_new_tv_entity(tmdb_id, file_context)
  end

  defp create_new_tv_entity(tmdb_id, file_context) do
    case Client.get_tv(tmdb_id) do
      {:ok, data} -> create_tv_entity(tmdb_id, data, file_context)
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Movie entity creation ---

  defp create_movie_entity(tmdb_id, data, file_context) do
    case data["belongs_to_collection"] do
      %{"id" => collection_id} ->
        create_movie_in_collection(tmdb_id, data, file_context, collection_id)

      _ ->
        create_standalone_movie(tmdb_id, data, file_context)
    end
  end

  defp create_standalone_movie(tmdb_id, data, file_context) do
    attrs = Mapper.movie_attrs(tmdb_id, data, file_context.file_path)

    with {:ok, entity} <- Ash.create(Entity, attrs, action: :create_from_tmdb),
         :ok <- create_identifier_with_race_retry(entity, tmdb_id),
         :ok <- create_images(entity, data) do
      {:ok, entity, :new}
    else
      {:race_lost, winner_entity_id} ->
        winner = Ash.get!(Entity, winner_entity_id)
        link_file_to_existing_entity(winner, :movie, file_context)

      error ->
        error
    end
  end

  # --- MovieSeries (collection) flow ---

  defp create_movie_in_collection(tmdb_id, movie_data, file_context, collection_id) do
    case find_existing_movie_series(collection_id) do
      {:ok, entity} ->
        position = determine_position(collection_id, tmdb_id)

        with {:ok, _movie} <-
               create_child_movie(entity, tmdb_id, movie_data, file_context, position),
             :ok <- create_movie_tmdb_identifier(entity, tmdb_id) do
          {:ok, entity, :new_child}
        end

      :not_found ->
        create_new_movie_series(tmdb_id, movie_data, file_context, collection_id)
    end
  end

  defp find_existing_movie_series(collection_id) do
    case Ash.read(Identifier,
           action: :find_by_tmdb_collection,
           args: %{collection_id: to_string(collection_id)}
         ) do
      {:ok, [%{entity: entity}]} -> {:ok, entity}
      _ -> :not_found
    end
  end

  defp create_new_movie_series(tmdb_id, movie_data, file_context, collection_id) do
    case Client.get_collection(collection_id) do
      {:ok, collection_data} ->
        attrs = Mapper.movie_series_attrs(collection_id, collection_data)

        with {:ok, entity} <- Ash.create(Entity, attrs, action: :create_from_tmdb),
             :ok <- create_collection_identifier_with_race_retry(entity, collection_id),
             :ok <- create_collection_images(entity, collection_data) do
          position = determine_position_from_parts(collection_data["parts"], tmdb_id)

          with {:ok, _movie} <-
                 create_child_movie(entity, tmdb_id, movie_data, file_context, position),
               :ok <- create_movie_tmdb_identifier(entity, tmdb_id) do
            {:ok, entity, :new}
          end
        else
          {:race_lost, winner_entity_id} ->
            winner = Ash.get!(Entity, winner_entity_id)
            position = determine_position_from_parts(collection_data["parts"], tmdb_id)

            with {:ok, _movie} <-
                   create_child_movie(winner, tmdb_id, movie_data, file_context, position),
                 :ok <- create_movie_tmdb_identifier(winner, tmdb_id) do
              {:ok, winner, :new_child}
            end

          error ->
            error
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_child_movie(entity, tmdb_id, movie_data, file_context, position) do
    attrs =
      Mapper.child_movie_attrs(entity.id, tmdb_id, movie_data, file_context.file_path, position)

    case Ash.create(Movie, attrs, action: :find_or_create) do
      {:ok, movie} ->
        if is_nil(movie.content_url) and not is_nil(file_context.file_path) do
          case Ash.update(movie, %{content_url: file_context.file_path}, action: :set_content_url) do
            {:ok, updated_movie} ->
              create_movie_images(updated_movie, movie_data)
              {:ok, updated_movie}

            {:error, reason} ->
              {:error, reason}
          end
        else
          create_movie_images(movie, movie_data)
          {:ok, movie}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_child_movie_exists(entity, file_context) do
    entity = Ash.load!(entity, [:movies])

    existing =
      Enum.find(entity.movies, fn movie -> movie.content_url == file_context.file_path end)

    if existing do
      {:ok, existing}
    else
      # Child movie not found by file path — this is a re-scan where the child movie
      # already exists but content_url may differ, or a race condition edge case.
      # Either way, the entity exists, so return ok.
      {:ok, nil}
    end
  end

  defp determine_position(collection_id, tmdb_id) do
    case Client.get_collection(collection_id) do
      {:ok, collection_data} ->
        determine_position_from_parts(collection_data["parts"], tmdb_id)

      {:error, _} ->
        0
    end
  end

  defp determine_position_from_parts(nil, _tmdb_id), do: 0

  defp determine_position_from_parts(parts, tmdb_id) do
    tmdb_id_int = if is_binary(tmdb_id), do: String.to_integer(tmdb_id), else: tmdb_id

    case Enum.find_index(parts, fn part -> part["id"] == tmdb_id_int end) do
      nil -> length(parts)
      index -> index
    end
  end

  defp create_movie_tmdb_identifier(entity, tmdb_id) do
    attrs = %{
      property_id: "tmdb",
      value: to_string(tmdb_id),
      entity_id: entity.id
    }

    case Ash.create(Identifier, attrs, action: :find_or_create) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_collection_identifier_with_race_retry(entity, collection_id) do
    attrs = %{
      property_id: "tmdb_collection",
      value: to_string(collection_id),
      entity_id: entity.id
    }

    case Ash.create(Identifier, attrs, action: :find_or_create) do
      {:ok, identifier} ->
        if identifier.entity_id == entity.id do
          :ok
        else
          Ash.destroy!(entity)
          {:race_lost, identifier.entity_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_collection_images(entity, collection_data) do
    images = Mapper.collection_image_attrs(entity.id, collection_data)

    Enum.reduce_while(images, :ok, fn attrs, :ok ->
      case Ash.create(Image, attrs, action: :find_or_create) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_movie_images(movie, movie_data) do
    images = Mapper.movie_image_attrs(movie.id, movie_data)

    Enum.each(images, fn attrs ->
      Ash.create(Image, attrs, action: :find_or_create_for_movie)
    end)
  end

  # --- TV entity creation ---

  defp create_tv_entity(tmdb_id, data, file_context) do
    attrs = Mapper.tv_attrs(tmdb_id, data)

    with {:ok, entity} <- Ash.create(Entity, attrs, action: :create_from_tmdb),
         :ok <- create_identifier_with_race_retry(entity, tmdb_id),
         :ok <- create_images(entity, data),
         :ok <- create_season_and_episode(entity, tmdb_id, file_context) do
      {:ok, entity, :new}
    else
      {:race_lost, winner_entity_id} ->
        winner = Ash.get!(Entity, winner_entity_id)
        link_file_to_existing_entity(winner, :tv, file_context)

      error ->
        error
    end
  end

  # --- Season/Episode for a single file ---

  defp create_season_and_episode(entity, tmdb_id, file_context) do
    season_number = file_context.season_number
    episode_number = file_context.episode_number

    if is_nil(season_number) or is_nil(episode_number) do
      :ok
    else
      case Client.get_season(tmdb_id, season_number) do
        {:ok, season_data} ->
          with {:ok, season} <- find_or_create_season(entity, season_data),
               :ok <- find_or_create_episode(season, season_data, file_context) do
            :ok
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp ensure_episode_exists(entity, file_context) do
    season_number = file_context.season_number
    episode_number = file_context.episode_number

    if is_nil(season_number) or is_nil(episode_number) do
      :ok
    else
      entity = Ash.load!(entity, [:identifiers])
      tmdb_identifier = Enum.find(entity.identifiers, &(&1.property_id == "tmdb"))

      if tmdb_identifier do
        tmdb_id = tmdb_identifier.value

        case Client.get_season(tmdb_id, season_number) do
          {:ok, season_data} ->
            with {:ok, season} <- find_or_create_season(entity, season_data),
                 :ok <- find_or_create_episode(season, season_data, file_context) do
              :ok
            end

          {:error, reason} ->
            {:error, reason}
        end
      else
        :ok
      end
    end
  end

  defp find_or_create_season(entity, season_data) do
    attrs = Mapper.season_attrs(entity.id, season_data)
    Ash.create(Season, attrs, action: :find_or_create)
  end

  defp find_or_create_episode(season, season_data, file_context) do
    attrs =
      Mapper.episode_attrs(
        season.id,
        season_data,
        file_context.episode_number,
        file_context.file_path
      )

    case Ash.create(Episode, attrs, action: :find_or_create) do
      {:ok, episode} ->
        if is_nil(episode.content_url) and not is_nil(file_context.file_path) do
          case Ash.update(episode, %{content_url: file_context.file_path},
                 action: :set_content_url
               ) do
            {:ok, _} -> :ok
            {:error, reason} -> {:error, reason}
          end
        else
          :ok
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Associations ---

  defp create_identifier_with_race_retry(entity, tmdb_id) do
    attrs = %{
      property_id: "tmdb",
      value: to_string(tmdb_id),
      entity_id: entity.id
    }

    case Ash.create(Identifier, attrs, action: :find_or_create) do
      {:ok, identifier} ->
        if identifier.entity_id == entity.id do
          :ok
        else
          Ash.destroy!(entity)
          {:race_lost, identifier.entity_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_images(entity, data) do
    images = Mapper.image_attrs(entity.id, data)

    Enum.reduce_while(images, :ok, fn attrs, :ok ->
      case Ash.create(Image, attrs, action: :find_or_create) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
