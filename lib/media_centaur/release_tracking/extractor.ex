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

  def extract_season_releases(season) do
    today = Date.utc_today()
    season_number = season["season_number"]

    (season["episodes"] || [])
    |> Enum.filter(fn episode ->
      case parse_date(episode["air_date"]) do
        nil -> true
        date -> Date.after?(date, today)
      end
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

  def extract_movie_status(response) do
    Map.get(@movie_status_map, response["status"], :unknown)
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
