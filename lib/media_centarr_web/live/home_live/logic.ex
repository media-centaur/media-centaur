defmodule MediaCentarrWeb.HomeLive.Logic do
  @moduledoc """
  Pure helpers for HomeLive — date math, hero selection, row assembly.
  No DB, no PubSub. Tested with `async: true` per ADR-030.

  HomeLive composes data from Library, ReleaseTracking, and WatchHistory
  contexts; this module shapes that data into the item maps each row
  component expects (see `MediaCentarrWeb.Components.{ContinueWatchingRow,
  ComingUpRow, PosterRow, HeroCard}`).
  """

  @typedoc "ContinueWatchingRow item shape"
  @type continue_item :: %{
          id: term(),
          name: String.t(),
          subtitle: String.t(),
          progress_pct: 0..100,
          backdrop_url: String.t() | nil
        }

  @doc """
  Returns `{monday, sunday}` of the week containing `date`. Defaults to today.
  """
  @spec coming_up_window(Date.t()) :: {Date.t(), Date.t()}
  def coming_up_window(date \\ Date.utc_today()) do
    monday = Date.add(date, 1 - Date.day_of_week(date))
    sunday = Date.add(monday, 6)
    {monday, sunday}
  end

  @doc """
  Picks one candidate from `candidates` deterministically based on `seed_date`.
  Same date → same pick (stable across calls during the day). Different
  dates rotate. Returns `nil` for empty list.
  """
  @spec select_hero([map()], Date.t()) :: map() | nil
  def select_hero(candidates, seed_date \\ Date.utc_today())
  def select_hero([], _date), do: nil

  def select_hero(candidates, %Date{} = date) do
    days = Date.diff(date, ~D[2024-01-01])
    Enum.at(candidates, rem(days, length(candidates)))
  end

  @doc "Shape Library progress rows into ContinueWatchingRow items."
  @spec continue_watching_items([map()]) :: [continue_item()]
  def continue_watching_items(progress_rows) do
    Enum.map(progress_rows, fn row ->
      %{
        id: row.entity_id,
        name: row.entity_name,
        subtitle: row.last_episode_label,
        progress_pct: row.progress_pct,
        backdrop_url: row.backdrop_url
      }
    end)
  end

  @doc """
  Shape ReleaseTracking releases into ComingUpRow items. `today` is used
  to format the relative day prefix in the subtitle (e.g. "MON · S04E01").
  """
  @spec coming_up_items([map()], Date.t()) :: [map()]
  def coming_up_items(releases, today) do
    Enum.map(releases, fn release ->
      %{
        id: release.item.id,
        name: release.item.name,
        subtitle: subtitle_for_release(release, today),
        badge: badge_for_status(release.status),
        backdrop_url: release.backdrop_url
      }
    end)
  end

  @doc "Shape Library entity rows into PosterRow items."
  @spec recently_added_items([map()]) :: [map()]
  def recently_added_items(entities) do
    Enum.map(entities, fn entity ->
      %{
        id: entity.id,
        name: entity.name,
        year: format_year(entity.year),
        poster_url: entity.poster_url
      }
    end)
  end

  @doc """
  Shape a single Library entity into the HeroCard item map. Returns nil
  for nil input.
  """
  @spec hero_card_item(map() | nil) :: map() | nil
  def hero_card_item(nil), do: nil

  def hero_card_item(entity) do
    %{
      id: entity.id,
      name: entity.name,
      year: format_year(entity.year),
      runtime: format_runtime(entity.runtime_minutes),
      genre_label: format_genres(entity.genres),
      overview: entity.overview,
      backdrop_url: entity.backdrop_url,
      play_url: "/library?selected=#{entity.id}&autoplay=1",
      detail_url: "/library?selected=#{entity.id}"
    }
  end

  # --- Private helpers ---

  defp subtitle_for_release(release, today) do
    day_prefix = day_prefix_for(release.air_date, today)
    season_episode = season_episode_label(release)

    [day_prefix, season_episode]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp day_prefix_for(nil, _today), do: nil

  defp day_prefix_for(%Date{} = date, today) do
    case Date.diff(date, today) do
      0 -> "TODAY"
      1 -> "TOMORROW"
      n when n in 2..6 -> date |> Calendar.strftime("%a") |> String.upcase()
      _ -> date |> Calendar.strftime("%b %d") |> String.upcase()
    end
  end

  defp season_episode_label(%{season_number: season, episode_number: episode})
       when not is_nil(season) and not is_nil(episode) do
    "S#{String.pad_leading("#{season}", 2, "0")}E#{String.pad_leading("#{episode}", 2, "0")}"
  end

  defp season_episode_label(_), do: nil

  defp badge_for_status(:grabbed), do: %{label: "Grabbed", variant: :success}
  defp badge_for_status(:downloading), do: %{label: "Downloading", variant: :info}
  defp badge_for_status(:pending), do: %{label: "Pending", variant: :info}
  defp badge_for_status(_), do: %{label: "Scheduled", variant: :default}

  defp format_year(nil), do: nil
  defp format_year(year) when is_integer(year), do: Integer.to_string(year)
  defp format_year(year) when is_binary(year), do: year

  defp format_runtime(nil), do: nil

  defp format_runtime(minutes) when is_integer(minutes) and minutes > 0 do
    hours = div(minutes, 60)
    mins = rem(minutes, 60)
    "#{hours}h #{mins}m"
  end

  defp format_runtime(_), do: nil

  defp format_genres(nil), do: nil
  defp format_genres([]), do: nil
  defp format_genres(genres) when is_list(genres), do: Enum.join(genres, " · ")
  defp format_genres(genres) when is_binary(genres), do: genres

  @doc """
  Map an inbound PubSub message to the home page sections that need reloading.
  Returns `[]` for messages the home page does not care about.

  Sections: `:continue_watching`, `:coming_up`, `:recently_added`.
  Hero is selected once per session and is intentionally not reloaded.
  """
  @spec section_reloaders(term()) :: [atom()]
  def section_reloaders({:entities_changed, _ids}), do: [:recently_added]
  def section_reloaders({:releases_updated, _ids}), do: [:coming_up]
  def section_reloaders({:item_removed, _tmdb_id, _tmdb_type}), do: [:coming_up]
  def section_reloaders({:release_ready, _item, _release}), do: [:coming_up]

  def section_reloaders({:watch_event_created, _event}), do: [:continue_watching]

  def section_reloaders(_), do: []
end
