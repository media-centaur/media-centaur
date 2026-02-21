defmodule MediaManager.Library.WatchedFile.Changes.FetchMetadata do
  use Ash.Resource.Change
  alias MediaManager.TMDB.Client
  alias MediaManager.Library.{Entity, Image, Identifier, Season, Episode}

  def change(changeset, _opts, _context) do
    tmdb_id = Ash.Changeset.get_attribute(changeset, :tmdb_id)
    parsed_type = Ash.Changeset.get_attribute(changeset, :parsed_type)
    file_path = Ash.Changeset.get_attribute(changeset, :file_path)
    season_number = Ash.Changeset.get_attribute(changeset, :season_number)
    episode_number = Ash.Changeset.get_attribute(changeset, :episode_number)

    file_context = %{
      file_path: file_path,
      season_number: season_number,
      episode_number: episode_number
    }

    case fetch_and_create(tmdb_id, parsed_type, file_context) do
      {:ok, entity, :new} ->
        changeset
        |> Ash.Changeset.change_attribute(:entity_id, entity.id)
        |> Ash.Changeset.change_attribute(:state, :fetching_images)

      {:ok, entity, :existing} ->
        changeset
        |> Ash.Changeset.change_attribute(:entity_id, entity.id)
        |> Ash.Changeset.change_attribute(:state, :complete)

      {:error, reason} ->
        changeset
        |> Ash.Changeset.change_attribute(:state, :error)
        |> Ash.Changeset.change_attribute(:error_message, inspect(reason))
    end
  end

  # --- Entry point: check for existing entity first ---

  defp fetch_and_create(tmdb_id, parsed_type, file_context) do
    case find_existing_entity(tmdb_id) do
      {:ok, entity} ->
        link_file_to_existing_entity(entity, parsed_type, file_context)

      :not_found ->
        create_new_entity(tmdb_id, parsed_type, file_context)
    end
  end

  defp find_existing_entity(tmdb_id) do
    case Ash.read(Identifier,
           action: :find_by_tmdb_id,
           args: %{tmdb_id: to_string(tmdb_id)}
         ) do
      {:ok, [%{entity: entity}]} -> {:ok, entity}
      _ -> :not_found
    end
  end

  # --- Reuse existing entity ---

  defp link_file_to_existing_entity(entity, :tv, file_context) do
    with :ok <- ensure_episode_exists(entity, file_context) do
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
    attrs = %{
      type: :movie,
      name: data["title"],
      description: data["overview"],
      date_published: data["release_date"],
      genres: extract_genre_names(data["genres"]),
      url: "https://www.themoviedb.org/movie/#{tmdb_id}",
      duration: minutes_to_iso8601(data["runtime"]),
      director: extract_director(data["credits"]),
      content_rating: extract_us_rating(data["release_dates"]),
      aggregate_rating_value: data["vote_average"],
      content_url: file_context.file_path
    }

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

  # --- TV entity creation ---

  defp create_tv_entity(tmdb_id, data, file_context) do
    attrs = %{
      type: :tv_series,
      name: data["name"],
      description: data["overview"],
      date_published: data["first_air_date"],
      genres: extract_genre_names(data["genres"]),
      url: "https://www.themoviedb.org/tv/#{tmdb_id}",
      number_of_seasons: data["number_of_seasons"],
      aggregate_rating_value: data["vote_average"]
    }

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
    season_number = season_data["season_number"]
    episodes = season_data["episodes"] || []

    attrs = %{
      entity_id: entity.id,
      season_number: season_number,
      name: season_data["name"],
      number_of_episodes: length(episodes)
    }

    Ash.create(Season, attrs, action: :find_or_create)
  end

  defp find_or_create_episode(season, season_data, file_context) do
    episode_number = file_context.episode_number
    episodes = season_data["episodes"] || []
    tmdb_episode = Enum.find(episodes, &(&1["episode_number"] == episode_number))

    attrs = %{
      season_id: season.id,
      episode_number: episode_number,
      name: tmdb_episode && tmdb_episode["name"],
      description: tmdb_episode && tmdb_episode["overview"],
      duration: tmdb_episode && minutes_to_iso8601(tmdb_episode["runtime"]),
      content_url: file_context.file_path
    }

    case Ash.create(Episode, attrs, action: :find_or_create) do
      {:ok, episode} ->
        # If the episode already existed but has no content_url, set it now
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
          # We either created it or it was already ours
          :ok
        else
          # Another processor won the race and created the identifier for a different entity.
          # Destroy our orphan entity and switch to using the winner's entity.
          Ash.destroy!(entity)
          {:race_lost, identifier.entity_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp create_images(entity, data) do
    images = build_image_attrs(entity.id, data)

    Enum.reduce_while(images, :ok, fn attrs, :ok ->
      case Ash.create(Image, attrs, action: :find_or_create) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp build_image_attrs(entity_id, data) do
    poster_path = data["poster_path"]
    backdrop_path = data["backdrop_path"]
    logos = get_in(data, ["images", "logos"]) || []
    logo = Enum.find(logos, &(&1["iso_639_1"] == "en")) || List.first(logos)

    [
      poster_path &&
        %{
          entity_id: entity_id,
          role: "poster",
          url: tmdb_image_url(poster_path),
          extension: "jpg"
        },
      backdrop_path &&
        %{
          entity_id: entity_id,
          role: "backdrop",
          url: tmdb_image_url(backdrop_path),
          extension: "jpg"
        },
      logo &&
        %{
          entity_id: entity_id,
          role: "logo",
          url: tmdb_image_url(logo["file_path"]),
          extension: "jpg"
        }
    ]
    |> Enum.reject(&is_nil/1)
  end

  # --- Helpers ---

  defp extract_genre_names(nil), do: []
  defp extract_genre_names(genres), do: Enum.map(genres, & &1["name"])

  defp extract_director(nil), do: nil

  defp extract_director(%{"crew" => crew}) do
    crew
    |> Enum.find(&(&1["department"] == "Directing" && &1["job"] == "Director"))
    |> then(&if &1, do: &1["name"], else: nil)
  end

  defp extract_us_rating(nil), do: nil

  defp extract_us_rating(%{"results" => results}) do
    us = Enum.find(results, &(&1["iso_3166_1"] == "US"))

    ((us && us["release_dates"]) || [])
    |> Enum.find_value(fn release_date ->
      release_date["certification"] != "" && release_date["certification"]
    end)
  end

  defp tmdb_image_url(nil), do: nil
  defp tmdb_image_url(path), do: "https://image.tmdb.org/t/p/original#{path}"

  defp minutes_to_iso8601(nil), do: nil

  defp minutes_to_iso8601(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "PT#{hours}H#{mins}M"
  end
end
