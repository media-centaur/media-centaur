defmodule MediaCentarr.TMDB.Mapper do
  @moduledoc """
  Maps raw TMDB API response data into domain-ready attribute maps
  suitable for creating library records. Isolates the TMDB JSON structure
  from the domain model.
  """

  @doc """
  Extracts domain attributes for a movie entity from TMDB movie data.
  """
  def movie_attrs(tmdb_id, movie, file_path) do
    %{
      type: :movie,
      name: movie["title"],
      description: movie["overview"],
      date_published: movie["release_date"],
      genres: extract_genre_names(movie["genres"]),
      url: tmdb_url(:movie, tmdb_id),
      duration: minutes_to_iso8601(movie["runtime"]),
      director: extract_director(movie["credits"]),
      cast: extract_cast(movie["credits"]),
      content_rating: extract_us_rating(movie["release_dates"]),
      aggregate_rating_value: movie["vote_average"],
      vote_count: movie["vote_count"],
      tagline: presence(movie["tagline"]),
      original_language: movie["original_language"],
      studio: extract_first_company(movie["production_companies"]),
      country_code: extract_first_country(movie["production_countries"]),
      content_url: file_path,
      status: parse_movie_status(movie["status"])
    }
  end

  @doc """
  Extracts domain attributes for a TV series entity from TMDB TV data.
  """
  def tv_attrs(tmdb_id, show) do
    %{
      type: :tv_series,
      name: show["name"],
      description: show["overview"],
      date_published: show["first_air_date"],
      genres: extract_genre_names(show["genres"]),
      url: tmdb_url(:tv, tmdb_id),
      number_of_seasons: show["number_of_seasons"],
      aggregate_rating_value: show["vote_average"],
      vote_count: show["vote_count"],
      tagline: presence(show["tagline"]),
      original_language: show["original_language"],
      studio: extract_first_company(show["production_companies"]),
      country_code: extract_first_country(show["production_countries"]),
      network: extract_first_network(show["networks"]),
      status: parse_tv_status(show["status"])
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
  def image_attrs(entity_id, tmdb_data), do: build_image_attrs(:entity_id, entity_id, tmdb_data)

  @doc """
  Extracts domain attributes for a MovieSeries entity from TMDB collection data.
  """
  def movie_series_attrs(collection_id, collection) do
    %{
      type: :movie_series,
      name: collection["name"],
      description: collection["overview"],
      url: tmdb_url(:collection, collection_id)
    }
  end

  @doc """
  Extracts domain attributes for a child Movie from TMDB movie data.
  """
  def child_movie_attrs(entity_id, tmdb_id, movie, file_path, position) do
    %{
      entity_id: entity_id,
      tmdb_id: to_string(tmdb_id),
      name: movie["title"],
      description: movie["overview"],
      date_published: movie["release_date"],
      url: tmdb_url(:movie, tmdb_id),
      duration: minutes_to_iso8601(movie["runtime"]),
      director: extract_director(movie["credits"]),
      content_rating: extract_us_rating(movie["release_dates"]),
      aggregate_rating_value: movie["vote_average"],
      content_url: file_path,
      position: position
    }
  end

  @doc """
  Builds image attribute maps for a child Movie (poster, backdrop, logo).
  Uses `movie_id` instead of `entity_id`.
  """
  def movie_image_attrs(movie_id, tmdb_data), do: build_image_attrs(:movie_id, movie_id, tmdb_data)

  @doc """
  Builds a thumb image attribute map for an episode from TMDB episode data.
  Returns a list with one entry if the episode has a `still_path`, or an empty list.
  """
  def episode_image_attrs(episode_id, tmdb_episode) do
    still_path = tmdb_episode && tmdb_episode["still_path"]

    if still_path do
      [
        %{
          episode_id: episode_id,
          role: "thumb",
          url: tmdb_image_url(still_path),
          extension: "jpg"
        }
      ]
    else
      []
    end
  end

  @doc """
  Builds image attribute maps for a MovieSeries entity from collection data.
  """
  def collection_image_attrs(entity_id, tmdb_data),
    do: build_image_attrs(:entity_id, entity_id, tmdb_data)

  defp build_image_attrs(owner_key, owner_id, tmdb_data) do
    poster_path = tmdb_data["poster_path"]
    backdrop_path = tmdb_data["backdrop_path"]
    logo_path = find_logo_path(tmdb_data)

    Enum.reject(
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
          %{owner_key => owner_id, role: "logo", url: tmdb_image_url(logo_path), extension: "png"}
      ],
      &is_nil/1
    )
  end

  defp find_logo_path(tmdb_data) do
    logos = get_in(tmdb_data, ["images", "logos"]) || []
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

  @tv_status_map %{
    "Returning Series" => :returning,
    "Ended" => :ended,
    "Canceled" => :canceled,
    "In Production" => :in_production,
    "Planned" => :planned
  }

  @movie_status_map %{
    "Released" => :released,
    "In Production" => :in_production,
    "Post Production" => :post_production,
    "Planned" => :planned,
    "Rumored" => :rumored,
    "Canceled" => :canceled
  }

  defp parse_tv_status(nil), do: nil
  defp parse_tv_status(status), do: Map.get(@tv_status_map, status)

  defp parse_movie_status(nil), do: nil
  defp parse_movie_status(status), do: Map.get(@movie_status_map, status)

  def extract_genre_names(nil), do: []
  def extract_genre_names(genres), do: Enum.map(genres, & &1["name"])

  def extract_director(nil), do: nil

  def extract_director(%{"crew" => crew}) do
    crew
    |> Enum.find(&(&1["department"] == "Directing" && &1["job"] == "Director"))
    |> then(&if &1, do: &1["name"])
  end

  @doc """
  Extracts the cast list from a TMDB credits payload. Returns a list of
  maps sorted by `order` ascending — the TMDB importance ranking.
  String keys (not atoms) so the value round-trips through SQLite/JSON
  without atom conversion friction.
  """
  def extract_cast(nil), do: []

  def extract_cast(%{"cast" => cast}) when is_list(cast) do
    cast
    |> Enum.sort_by(& &1["order"])
    |> Enum.map(fn person ->
      %{
        "name" => person["name"],
        "character" => person["character"],
        "tmdb_person_id" => person["id"],
        "profile_path" => person["profile_path"],
        "order" => person["order"]
      }
    end)
  end

  def extract_cast(_), do: []

  def extract_us_rating(nil), do: nil

  def extract_us_rating(%{"results" => results}) do
    release_dates =
      case Enum.find(results, &(&1["iso_3166_1"] == "US")) do
        %{"release_dates" => dates} -> dates
        _ -> []
      end

    Enum.find_value(release_dates, fn release_date ->
      release_date["certification"] != "" && release_date["certification"]
    end)
  end

  def minutes_to_iso8601(nil), do: nil

  def minutes_to_iso8601(minutes) when is_integer(minutes) do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "PT#{hours}H#{mins}M"
  end

  def extract_first_company(nil), do: nil
  def extract_first_company([]), do: nil
  def extract_first_company([%{"name" => name} | _]), do: name
  def extract_first_company(_), do: nil

  def extract_first_country(nil), do: nil
  def extract_first_country([]), do: nil
  def extract_first_country([%{"iso_3166_1" => code} | _]), do: code
  def extract_first_country(_), do: nil

  def extract_first_network(nil), do: nil
  def extract_first_network([]), do: nil
  def extract_first_network([%{"name" => name} | _]), do: name
  def extract_first_network(_), do: nil

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value
end
