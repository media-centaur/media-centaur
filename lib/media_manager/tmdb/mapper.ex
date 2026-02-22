defmodule MediaManager.TMDB.Mapper do
  @moduledoc """
  Maps raw TMDB API response data into domain-ready attribute maps
  suitable for creating Ash resources. Isolates the TMDB JSON structure
  from the domain model.
  """

  @doc """
  Extracts domain attributes for a movie entity from TMDB movie data.
  """
  def movie_attrs(tmdb_id, data, file_path) do
    %{
      type: :movie,
      name: data["title"],
      description: data["overview"],
      date_published: data["release_date"],
      genres: extract_genre_names(data["genres"]),
      url: tmdb_url(:movie, tmdb_id),
      duration: minutes_to_iso8601(data["runtime"]),
      director: extract_director(data["credits"]),
      content_rating: extract_us_rating(data["release_dates"]),
      aggregate_rating_value: data["vote_average"],
      content_url: file_path
    }
  end

  @doc """
  Extracts domain attributes for a TV series entity from TMDB TV data.
  """
  def tv_attrs(tmdb_id, data) do
    %{
      type: :tv_series,
      name: data["name"],
      description: data["overview"],
      date_published: data["first_air_date"],
      genres: extract_genre_names(data["genres"]),
      url: tmdb_url(:tv, tmdb_id),
      number_of_seasons: data["number_of_seasons"],
      aggregate_rating_value: data["vote_average"]
    }
  end

  @doc """
  Extracts season attributes from TMDB season data.
  """
  def season_attrs(entity_id, season_data) do
    episodes = season_data["episodes"] || []

    %{
      entity_id: entity_id,
      season_number: season_data["season_number"],
      name: season_data["name"],
      number_of_episodes: length(episodes)
    }
  end

  @doc """
  Extracts episode attributes from TMDB episode data within a season response.
  """
  def episode_attrs(season_id, season_data, episode_number, file_path) do
    episodes = season_data["episodes"] || []
    tmdb_episode = Enum.find(episodes, &(&1["episode_number"] == episode_number))

    %{
      season_id: season_id,
      episode_number: episode_number,
      name: tmdb_episode && tmdb_episode["name"],
      description: tmdb_episode && tmdb_episode["overview"],
      duration: tmdb_episode && minutes_to_iso8601(tmdb_episode["runtime"]),
      content_url: file_path
    }
  end

  @doc """
  Builds a list of image attribute maps from TMDB entity data (poster, backdrop, logo).
  """
  def image_attrs(entity_id, data), do: build_image_attrs(:entity_id, entity_id, data)

  @doc """
  Extracts domain attributes for a MovieSeries entity from TMDB collection data.
  """
  def movie_series_attrs(collection_id, data) do
    %{
      type: :movie_series,
      name: data["name"],
      description: data["overview"],
      url: tmdb_url(:collection, collection_id)
    }
  end

  @doc """
  Extracts domain attributes for a child Movie from TMDB movie data.
  """
  def child_movie_attrs(entity_id, tmdb_id, data, file_path, position) do
    %{
      entity_id: entity_id,
      tmdb_id: to_string(tmdb_id),
      name: data["title"],
      description: data["overview"],
      date_published: data["release_date"],
      url: tmdb_url(:movie, tmdb_id),
      duration: minutes_to_iso8601(data["runtime"]),
      director: extract_director(data["credits"]),
      content_rating: extract_us_rating(data["release_dates"]),
      aggregate_rating_value: data["vote_average"],
      content_url: file_path,
      position: position
    }
  end

  @doc """
  Builds image attribute maps for a child Movie (poster, backdrop, logo).
  Uses `movie_id` instead of `entity_id`.
  """
  def movie_image_attrs(movie_id, data), do: build_image_attrs(:movie_id, movie_id, data)

  @doc """
  Builds image attribute maps for a MovieSeries entity from collection data.
  """
  def collection_image_attrs(entity_id, data), do: build_image_attrs(:entity_id, entity_id, data)

  defp build_image_attrs(owner_key, owner_id, data) do
    poster_path = data["poster_path"]
    backdrop_path = data["backdrop_path"]
    logo_path = find_logo_path(data)

    [
      poster_path &&
        %{
          owner_key => owner_id,
          role: "poster",
          url: tmdb_image_url(poster_path),
          extension: "jpg"
        },
      backdrop_path &&
        %{
          owner_key => owner_id,
          role: "backdrop",
          url: tmdb_image_url(backdrop_path),
          extension: "jpg"
        },
      logo_path &&
        %{owner_key => owner_id, role: "logo", url: tmdb_image_url(logo_path), extension: "jpg"}
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp find_logo_path(data) do
    logos = get_in(data, ["images", "logos"]) || []
    logo = Enum.find(logos, &(&1["iso_639_1"] == "en")) || List.first(logos)
    logo && logo["file_path"]
  end

  @doc "Builds a TMDB web URL for the given type and ID."
  def tmdb_url(:movie, tmdb_id), do: "https://www.themoviedb.org/movie/#{tmdb_id}"
  def tmdb_url(:tv, tmdb_id), do: "https://www.themoviedb.org/tv/#{tmdb_id}"
  def tmdb_url(:collection, id), do: "https://www.themoviedb.org/collection/#{id}"

  @doc "Builds a full TMDB image CDN URL from a relative path."
  def tmdb_image_url(nil), do: nil
  def tmdb_image_url(path), do: "https://image.tmdb.org/t/p/original#{path}"

  def extract_genre_names(nil), do: []
  def extract_genre_names(genres), do: Enum.map(genres, & &1["name"])

  def extract_director(nil), do: nil

  def extract_director(%{"crew" => crew}) do
    crew
    |> Enum.find(&(&1["department"] == "Directing" && &1["job"] == "Director"))
    |> then(&if &1, do: &1["name"], else: nil)
  end

  def extract_us_rating(nil), do: nil

  def extract_us_rating(%{"results" => results}) do
    us = Enum.find(results, &(&1["iso_3166_1"] == "US"))

    ((us && us["release_dates"]) || [])
    |> Enum.find_value(fn release_date ->
      release_date["certification"] != "" && release_date["certification"]
    end)
  end

  def minutes_to_iso8601(nil), do: nil

  def minutes_to_iso8601(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "PT#{hours}H#{mins}M"
  end
end
