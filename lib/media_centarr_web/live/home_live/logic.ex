defmodule MediaCentarrWeb.HomeLive.Logic do
  @moduledoc """
  Pure helpers for HomeLive — date math, hero selection, row assembly.
  No DB, no PubSub. Tested with `async: true` per ADR-030.

  HomeLive composes data from Library, ReleaseTracking, and WatchHistory
  contexts; this module shapes that data into the item maps each row
  component expects (see `MediaCentarrWeb.Components.{ContinueWatchingRow,
  ComingUpMarquee, PosterRow, HeroCard}`).
  """

  alias MediaCentarrWeb.Components.{ComingUpMarquee, ContinueWatchingRow, HeroCard, PosterRow}

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
  @spec continue_watching_items([map()]) :: [ContinueWatchingRow.Item.t()]
  def continue_watching_items(progress_rows) do
    Enum.map(progress_rows, fn row ->
      %ContinueWatchingRow.Item{
        id: row.entity_id,
        entity_id: row.entity_id,
        name: row.entity_name,
        progress_pct: row.progress_pct,
        backdrop_url: row.backdrop_url,
        logo_url: Map.get(row, :logo_url),
        autoplay: false
      }
    end)
  end

  @doc """
  Same as `continue_watching_items/1`, but pins entities the user is
  currently playing (any non-stopped state in `playback`) to the front
  of the row, preserving the original Continue Watching order both
  among the pinned items and among the rest.

  `playback` is the `apply_playback_change/5`-shaped map keyed by
  `entity_id`; the value's `:state` is what we read.
  """
  @spec continue_watching_items([map()], map()) :: [ContinueWatchingRow.Item.t()]
  def continue_watching_items(progress_rows, playback) when is_map(playback) do
    items = continue_watching_items(progress_rows)
    {pinned, rest} = Enum.split_with(items, &active_session?(&1.entity_id, playback))
    pinned ++ rest
  end

  defp active_session?(entity_id, playback) do
    case Map.get(playback, entity_id) do
      nil -> false
      %{state: :stopped} -> false
      _entry -> true
    end
  end

  @doc """
  Shape ReleaseTracking releases into a `ComingUpMarquee.Marquee` view-model.

  Behaviour:

    * Deduplicates releases by series (a single show with seven upcoming
      episodes appears once, not seven times).
    * The soonest release becomes the hero. Up to three other distinct
      shows fill the secondary tiles, ordered by air date.
    * The hero carries a `rollup` line ("+ 6 more this season",
      "season premiere", or both); secondary tiles carry a `sub`
      ("S0xE0y" or "+ N more").
    * Eyebrow text is "Tonight" / "Tomorrow" / abbreviated weekday /
      absolute "Mon DD" relative to `today`. Hero eyebrows include the
      season/episode label; secondary eyebrows just carry the day part
      and put the episode label in `sub`.
    * An empty input returns `%Marquee{hero: nil, secondaries: []}` so
      the caller can render nothing without special-casing.
  """
  @spec coming_up_marquee([map()], Date.t()) :: ComingUpMarquee.Marquee.t()
  def coming_up_marquee(releases, today) do
    by_series = Enum.group_by(releases, & &1.item.id)

    earliest_per_series =
      by_series
      |> Enum.map(fn {_series_id, releases} ->
        Enum.min_by(releases, & &1.air_date, Date)
      end)
      |> Enum.sort_by(& &1.air_date, Date)

    case earliest_per_series do
      [] ->
        %ComingUpMarquee.Marquee{hero: nil, secondaries: []}

      [hero_release | rest] ->
        hero =
          build_marquee_item(
            hero_release,
            length(by_series[hero_release.item.id]),
            today,
            :hero
          )

        secondaries =
          rest
          |> Enum.take(3)
          |> Enum.map(fn release ->
            build_marquee_item(
              release,
              length(by_series[release.item.id]),
              today,
              :secondary
            )
          end)

        %ComingUpMarquee.Marquee{hero: hero, secondaries: secondaries}
    end
  end

  @doc "Shape Library entity rows into PosterRow items."
  @spec recently_added_items([map()]) :: [PosterRow.Item.t()]
  def recently_added_items(entities) do
    Enum.map(entities, fn entity ->
      %PosterRow.Item{
        id: entity.id,
        entity_id: entity.id,
        name: entity.name,
        year: format_year(entity.year),
        poster_url: entity.poster_url
      }
    end)
  end

  @doc """
  Shape a single Library entity into the HeroCard item. Returns nil for
  nil input.
  """
  @spec hero_card_item(map() | nil) :: HeroCard.Item.t() | nil
  def hero_card_item(nil), do: nil

  def hero_card_item(entity) do
    %HeroCard.Item{
      id: entity.id,
      entity_id: entity.id,
      name: entity.name,
      year: format_year(entity.year),
      runtime: format_runtime(entity.runtime_minutes),
      genre_label: format_genres(entity.genres),
      overview: entity.overview,
      backdrop_url: entity.backdrop_url,
      logo_url: Map.get(entity, :logo_url)
    }
  end

  # --- Private helpers ---

  defp build_marquee_item(release, series_count, today, role) do
    more_count = series_count - 1
    episode_label = season_episode_label(release)
    day_part = day_part_for(release.air_date, today)

    eyebrow =
      case role do
        :hero -> [day_part, episode_label] |> Enum.reject(&is_nil/1) |> Enum.join(" · ")
        :secondary -> day_part
      end

    rollup = if role == :hero, do: rollup_text(release, more_count)
    sub = if role == :secondary, do: sub_text(more_count, episode_label)

    %ComingUpMarquee.Item{
      id: release.item.id,
      entity_id: Map.get(release.item, :entity_id),
      name: release.item.name,
      eyebrow: eyebrow,
      badge: badge_for_status(release.status),
      backdrop_url: Map.get(release, :backdrop_url),
      logo_url: Map.get(release, :logo_url),
      rollup: rollup,
      sub: sub
    }
  end

  defp day_part_for(nil, _today), do: nil

  defp day_part_for(%Date{} = date, today) do
    case Date.diff(date, today) do
      0 -> "Tonight"
      1 -> "Tomorrow"
      n when n in 2..6 -> Calendar.strftime(date, "%a")
      _ -> Calendar.strftime(date, "%b %-d")
    end
  end

  defp rollup_text(release, more_count) do
    premiere? = release.episode_number == 1

    cond do
      more_count > 0 and premiere? -> "+ #{more_count} more · season premiere"
      more_count > 0 -> "+ #{more_count} more this season"
      premiere? -> "season premiere"
      true -> nil
    end
  end

  defp sub_text(more_count, episode_label) do
    cond do
      more_count > 0 -> "+ #{more_count} more"
      episode_label -> episode_label
      true -> nil
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
  # Scheduled is the implicit baseline of every Coming Up tile — render no
  # badge for it. Reserve the badge for differentiating action states.
  defp badge_for_status(_), do: nil

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
  def section_reloaders({:entities_changed, %{entity_ids: _ids}}), do: [:recently_added]
  def section_reloaders({:releases_updated, _ids}), do: [:coming_up]
  def section_reloaders({:item_removed, _tmdb_id, _tmdb_type}), do: [:coming_up]
  def section_reloaders({:release_ready, _item, _release}), do: [:coming_up]

  def section_reloaders({:watch_event_created, _event}), do: [:continue_watching]

  def section_reloaders({:entity_progress_updated, _payload}), do: [:continue_watching]

  def section_reloaders({:playback_state_changed, _payload}), do: [:continue_watching]

  def section_reloaders(_), do: []
end
