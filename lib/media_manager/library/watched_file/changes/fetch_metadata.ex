defmodule MediaManager.Library.WatchedFile.Changes.FetchMetadata do
  use Ash.Resource.Change
  alias MediaManager.TMDB.Client
  alias MediaManager.Library.{Entity, Image, Identifier, Season, Episode}

  def change(changeset, _opts, _context) do
    tmdb_id = Ash.Changeset.get_attribute(changeset, :tmdb_id)
    parsed_type = Ash.Changeset.get_attribute(changeset, :parsed_type)

    case fetch_and_create(tmdb_id, parsed_type) do
      {:ok, entity} ->
        changeset
        |> Ash.Changeset.change_attribute(:entity_id, entity.id)
        |> Ash.Changeset.change_attribute(:state, :fetching_images)

      {:error, reason} ->
        changeset
        |> Ash.Changeset.change_attribute(:state, :error)
        |> Ash.Changeset.change_attribute(:error_message, inspect(reason))
    end
  end

  # --- Movie ---

  defp fetch_and_create(tmdb_id, type) when type in [:movie, :unknown] do
    case Client.get_movie(tmdb_id) do
      {:ok, data} -> create_movie_entity(tmdb_id, data)
      {:error, _} when type == :unknown -> fetch_and_create_tv(tmdb_id)
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_and_create(tmdb_id, :tv), do: fetch_and_create_tv(tmdb_id)

  defp fetch_and_create_tv(tmdb_id) do
    case Client.get_tv(tmdb_id) do
      {:ok, data} -> create_tv_entity(tmdb_id, data)
      {:error, reason} -> {:error, reason}
    end
  end

  # --- Movie entity creation ---

  defp create_movie_entity(tmdb_id, data) do
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
      aggregate_rating_value: data["vote_average"]
    }

    with {:ok, entity} <- Ash.create(Entity, attrs, action: :create_from_tmdb),
         :ok <- create_identifier(entity, tmdb_id),
         :ok <- create_images(entity, data) do
      {:ok, entity}
    end
  end

  # --- TV entity creation ---

  defp create_tv_entity(tmdb_id, data) do
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
         :ok <- create_identifier(entity, tmdb_id),
         :ok <- create_images(entity, data),
         :ok <- create_seasons(entity, tmdb_id, data["seasons"] || []) do
      {:ok, entity}
    end
  end

  # --- Associations ---

  defp create_identifier(entity, tmdb_id) do
    case Ash.create(Identifier, %{
           property_id: "tmdb",
           value: to_string(tmdb_id),
           entity_id: entity.id
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp create_images(entity, data) do
    images = build_image_attrs(entity.id, data)

    Enum.reduce_while(images, :ok, fn attrs, :ok ->
      case Ash.create(Image, attrs) do
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

  defp create_seasons(entity, tmdb_id, tmdb_seasons) do
    real_seasons = Enum.reject(tmdb_seasons, &(&1["season_number"] == 0))

    Enum.reduce_while(real_seasons, :ok, fn season_stub, :ok ->
      season_number = season_stub["season_number"]

      case Client.get_season(tmdb_id, season_number) do
        {:ok, season_data} ->
          case create_season(entity, season_data) do
            :ok -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  defp create_season(entity, season_data) do
    episodes = season_data["episodes"] || []

    attrs = %{
      entity_id: entity.id,
      season_number: season_data["season_number"],
      name: season_data["name"],
      number_of_episodes: length(episodes)
    }

    with {:ok, season} <- Ash.create(Season, attrs) do
      create_episodes(season, episodes)
    end
  end

  defp create_episodes(season, episodes) do
    Enum.reduce_while(episodes, :ok, fn episode, :ok ->
      attrs = %{
        season_id: season.id,
        episode_number: episode["episode_number"],
        name: episode["name"],
        description: episode["overview"],
        duration: minutes_to_iso8601(episode["runtime"])
      }

      case Ash.create(Episode, attrs) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
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
