defmodule MediaCentaur.ReleaseTracking.Extractor do
  @moduledoc """
  Pure functions that extract release tracking data from raw TMDB JSON responses.
  """

  alias MediaCentaur.TMDB.Mapper

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

  def extract_tv_status(response) do
    Map.get(@tv_status_map, response["status"], :unknown)
  end

  def extract_tv_releases(response) do
    case response["next_episode_to_air"] do
      nil -> []
      episode -> [parse_episode_release(episode)]
    end
  end

  def extract_movie_status(response) do
    Map.get(@movie_status_map, response["status"], :unknown)
  end

  @doc """
  Extracts US theatrical (type 3), digital (type 4), and physical (type 5)
  release dates from a TMDB movie response. Falls back to the simple
  `release_date` field if no detailed US dates are available.
  """
  def extract_movie_release_dates(response) do
    title = response["title"]

    case Mapper.us_typed_release_dates(response) do
      [] ->
        [
          %{
            air_date: parse_date(response["release_date"]),
            title: title,
            release_type: "theatrical"
          }
        ]

      typed ->
        Enum.map(typed, fn %{release_type: release_type, date: date} ->
          %{air_date: date, release_type: release_type, title: title}
        end)
    end
  end

  def extract_collection_releases(collection) do
    today = Date.utc_today()

    (collection["parts"] || [])
    |> Enum.filter(fn part ->
      case parse_date(part["release_date"]) do
        nil -> true
        date -> Date.after?(date, today)
      end
    end)
    |> Enum.map(fn part ->
      %{
        air_date: parse_date(part["release_date"]),
        title: part["title"],
        tmdb_id: part["id"]
      }
    end)
  end

  @doc """
  Returns all episodes from a TMDB season response that come after the given
  last_season/last_episode. Does NOT filter by date -- caller decides released vs upcoming.
  """
  def extract_episodes_since(season_data, last_season, last_episode) do
    season_number = season_data["season_number"]

    (season_data["episodes"] || [])
    |> Enum.filter(fn episode ->
      episode_number = episode["episode_number"]

      season_number > last_season ||
        (season_number == last_season && episode_number > last_episode)
    end)
    |> Enum.map(fn episode ->
      %{
        air_date: parse_date(episode["air_date"]),
        season_number: season_number,
        episode_number: episode["episode_number"],
        title: episode["name"]
      }
    end)
  end

  def extract_poster_path(response), do: response["poster_path"]

  @doc """
  Picks the best logo from a TMDB response's `images.logos` array. Prefers
  the English-localised logo (`iso_639_1 == "en"`); falls back to the first
  available logo. Returns `nil` if no logos are present.

  Requires the response to have been fetched with `append_to_response: "images"`
  (the `MediaCentaur.TMDB.Client` calls do this).
  """
  @spec extract_logo_path(map()) :: String.t() | nil
  def extract_logo_path(response) do
    logos = get_in(response, ["images", "logos"]) || []
    logo = Enum.find(logos, &(&1["iso_639_1"] == "en")) || List.first(logos)
    logo && logo["file_path"]
  end

  defp parse_episode_release(episode) do
    %{
      air_date: parse_date(episode["air_date"]),
      season_number: episode["season_number"],
      episode_number: episode["episode_number"],
      title: episode["name"]
    }
  end

  defp parse_date(nil), do: nil
  defp parse_date(""), do: nil

  defp parse_date(date_string) when is_binary(date_string) do
    case Date.from_iso8601(date_string) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
