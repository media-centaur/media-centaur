defmodule MediaCentaur.ReleaseTracking.Extractor do
  @moduledoc """
  Pure functions that extract release tracking data from raw TMDB JSON responses.
  """

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
  Extracts US theatrical (type 3) and digital (type 4) release dates from a
  TMDB movie response. Falls back to the simple `release_date` field if no
  detailed US dates are available.
  """
  def extract_movie_release_dates(response) do
    title = response["title"]

    case extract_us_typed_dates(response) do
      [] ->
        [
          %{
            air_date: parse_date(response["release_date"]),
            title: title,
            release_type: "theatrical"
          }
        ]

      dates ->
        dates |> Enum.map(&Map.put(&1, :title, title))
    end
  end

  @tracked_release_types %{3 => "theatrical", 4 => "digital"}

  defp extract_us_typed_dates(%{"release_dates" => %{"results" => results}})
       when is_list(results) do
    us_entry = Enum.find(results, &(&1["iso_3166_1"] == "US"))

    case us_entry do
      %{"release_dates" => dates} when is_list(dates) ->
        dates
        |> Enum.filter(&Map.has_key?(@tracked_release_types, &1["type"]))
        |> Enum.map(fn date ->
          %{
            air_date: parse_datetime_date(date["release_date"]),
            release_type: Map.fetch!(@tracked_release_types, date["type"])
          }
        end)

      _ ->
        []
    end
  end

  defp extract_us_typed_dates(_), do: []

  defp parse_datetime_date(nil), do: nil
  defp parse_datetime_date(""), do: nil

  defp parse_datetime_date(datetime_string) do
    # TMDB returns "2026-05-10T00:00:00.000Z" — extract the date portion
    datetime_string
    |> String.slice(0, 10)
    |> parse_date()
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
    |> Enum.filter(fn ep ->
      ep_num = ep["episode_number"]

      season_number > last_season ||
        (season_number == last_season && ep_num > last_episode)
    end)
    |> Enum.map(fn ep ->
      %{
        air_date: parse_date(ep["air_date"]),
        season_number: season_number,
        episode_number: ep["episode_number"],
        title: ep["name"]
      }
    end)
  end

  def extract_poster_path(response), do: response["poster_path"]

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
