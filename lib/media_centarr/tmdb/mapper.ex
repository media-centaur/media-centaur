defmodule MediaCentarr.TMDB.Mapper do
  @moduledoc """
  Maps raw TMDB API response data into domain-ready attribute maps
  suitable for creating library records. Isolates the TMDB JSON structure
  from the domain model.
  """

  @doc """
  Extracts domain attributes for a movie entity from TMDB movie data.

  The `file_path` argument is unused by the entity attrs — the on-disk
  path is recorded on the WatchedFile linked to the Movie's
  PlayableItem (Library Schema v2 Phase 2 Task I). The arity is kept
  so existing pipeline call sites pass the path through; downstream
  `link_file/2` consumes it via `event.file_path`.
  """
  def movie_attrs(tmdb_id, movie, _file_path) do
    %{
      type: :movie,
      tmdb_id: to_string(tmdb_id),
      imdb_id: presence(movie["imdb_id"]),
      name: movie["title"],
      description: movie["overview"],
      date_published: parse_date(movie["release_date"]),
      genres: extract_genre_names(movie["genres"]),
      url: tmdb_url(:movie, tmdb_id),
      duration_seconds: minutes_to_seconds(movie["runtime"]),
      director: extract_director(movie["credits"]),
      cast: extract_cast(movie["credits"]),
      crew: extract_crew(movie["credits"]),
      content_rating: extract_us_rating(movie["release_dates"]),
      aggregate_rating_value: movie["vote_average"],
      vote_count: movie["vote_count"],
      tagline: presence(movie["tagline"]),
      original_language: movie["original_language"],
      studio: extract_first_company(movie["production_companies"]),
      country_code: extract_first_country(movie["production_countries"]),
      status: parse_movie_status(movie["status"])
    }
  end

  @doc """
  Extracts domain attributes for a TV series entity from TMDB TV data.

  Expects `show` to optionally include `aggregate_credits` (cast across
  all seasons), `external_ids` (for `imdb_id`), and `created_by` (the
  show's creators). These are populated by `TMDB.Client.get_tv/2` via
  `append_to_response`.
  """
  def tv_attrs(tmdb_id, show) do
    %{
      type: :tv_series,
      tmdb_id: to_string(tmdb_id),
      imdb_id: extract_tv_imdb_id(show),
      name: show["name"],
      description: show["overview"],
      date_published: parse_date(show["first_air_date"]),
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
      status: parse_tv_status(show["status"]),
      cast: extract_cast(show["aggregate_credits"]),
      crew: extract_creators(show["created_by"])
    }
  end

  defp extract_tv_imdb_id(%{"external_ids" => %{"imdb_id" => imdb_id}}), do: presence(imdb_id)
  defp extract_tv_imdb_id(_), do: nil

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

  The `file_path` argument is unused by the entity attrs — the on-disk
  path is recorded on the WatchedFile linked to the Episode's
  PlayableItem (Library Schema v2 Phase 2 Task I). The arity is kept
  so existing pipeline call sites pass the path through; downstream
  `link_file/2` consumes it via `event.file_path`.
  """
  def episode_attrs(season_id, season_data, episode_number, _file_path) do
    episodes = season_data["episodes"] || []
    tmdb_episode = Enum.find(episodes, &(&1["episode_number"] == episode_number))

    %{
      season_id: season_id,
      episode_number: episode_number,
      name: tmdb_episode && tmdb_episode["name"],
      description: tmdb_episode && tmdb_episode["overview"],
      duration_seconds: tmdb_episode && minutes_to_seconds(tmdb_episode["runtime"])
    }
  end

  @doc """
  Extracts domain attributes for a MovieSeries entity from TMDB collection data.

  TMDB's `/collection/{id}` endpoint is sparse — it returns `name`,
  `overview`, image paths, and the `parts` list, but no `tagline`,
  `status`, `studio`, `country_code`, `original_language`, `vote_count`,
  or top-level credits (those live per-movie on the parts). The
  schema-level symmetry with `TVSeries` (Phase 1 Task 4 of the Library
  Schema v2 campaign) is preserved by ingest writing empty `cast`/`crew`
  lists; the other scalars are left absent (i.e. `nil` post-cast).
  Future enrichment can aggregate from the constituent movies.
  """
  def movie_series_attrs(collection_id, collection) do
    %{
      type: :movie_series,
      tmdb_id: to_string(collection_id),
      name: collection["name"],
      description: collection["overview"],
      url: tmdb_url(:collection, collection_id),
      cast: [],
      crew: []
    }
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

  Handles both shapes:

    * Movie `credits.cast`: each entry has a top-level `character`.
    * TV `aggregate_credits.cast`: each entry has `roles: [{character,
      episode_count}]` — we pick the first role (highest episode count
      by TMDB convention) for the displayed character name.

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
        "character" => extract_cast_character(person),
        "tmdb_person_id" => person["id"],
        "profile_path" => person["profile_path"],
        "order" => person["order"]
      }
    end)
  end

  def extract_cast(_), do: []

  defp extract_cast_character(%{"character" => character}) when is_binary(character), do: character

  defp extract_cast_character(%{"roles" => [%{"character" => character} | _]}), do: character
  defp extract_cast_character(_), do: nil

  @doc """
  Maps TMDB TV `created_by` entries into the same crew-row shape used
  for movie crew. Each creator becomes a `Creator`-job row so the More
  info panel can render them with the same `Enum.filter(crew, &(&1["job"] == "..."))`
  pattern movies use for directors and writers.
  """
  def extract_creators(nil), do: []

  def extract_creators(creators) when is_list(creators) do
    Enum.map(creators, fn person ->
      %{
        "tmdb_person_id" => person["id"],
        "name" => person["name"],
        "job" => "Creator",
        "department" => "Creator",
        "profile_path" => person["profile_path"]
      }
    end)
  end

  def extract_creators(_), do: []

  @crew_jobs %{
    "Director" => 0,
    "Screenplay" => 1,
    "Writer" => 2,
    "Story" => 3,
    "Original Music Composer" => 4,
    "Director of Photography" => 5,
    "Editor" => 6,
    "Producer" => 7
  }

  @doc """
  Extracts the structured crew list from a TMDB credits payload. Filters
  to roles users care about on the More info panel (director, writers,
  composer, DP, editor, producer) and sorts by a fixed display priority
  so directors appear above writers, etc. String keys (not atoms) so the
  value round-trips through SQLite/JSON without atom conversion friction.
  """
  def extract_crew(nil), do: []

  def extract_crew(%{"crew" => crew}) when is_list(crew) do
    crew
    |> Enum.filter(&Map.has_key?(@crew_jobs, &1["job"]))
    |> Enum.sort_by(&{Map.fetch!(@crew_jobs, &1["job"]), &1["name"]})
    |> Enum.map(fn person ->
      %{
        "tmdb_person_id" => person["id"],
        "name" => person["name"],
        "job" => person["job"],
        "department" => person["department"],
        "profile_path" => person["profile_path"]
      }
    end)
  end

  def extract_crew(_), do: []

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

  @doc """
  Converts a TMDB `runtime` value (minutes) into integer seconds. TMDB
  returns `nil` (or omits the key) for unreleased / in-production titles
  whose runtime hasn't been recorded yet, and sometimes returns `0` for
  the same condition — both map to `nil` so downstream "no duration
  known" guards (e.g. `detail_panel.duration_or_nil/1`) work uniformly.
  Used by `movie_attrs/3` and `episode_attrs/4` at the TMDB→domain
  boundary to feed `Movie.duration_seconds` / `Episode.duration_seconds`.
  """
  @spec minutes_to_seconds(integer() | nil) :: integer() | nil
  def minutes_to_seconds(nil), do: nil
  def minutes_to_seconds(0), do: nil
  def minutes_to_seconds(minutes) when is_integer(minutes), do: minutes * 60

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

  @doc """
  Parses an ISO 8601 date string from a TMDB payload (e.g. `release_date`,
  `first_air_date`) into a `Date` struct. TMDB returns `""` for unreleased
  titles — that and `nil` both map to `nil`. Malformed values raise so the
  pipeline surfaces a clear error rather than silently dropping the field.
  """
  @spec parse_date(String.t() | nil) :: Date.t() | nil
  def parse_date(nil), do: nil
  def parse_date(""), do: nil
  def parse_date(iso) when is_binary(iso), do: Date.from_iso8601!(iso)
end
