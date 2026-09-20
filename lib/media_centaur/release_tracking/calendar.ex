defmodule MediaCentaur.ReleaseTracking.Calendar do
  @moduledoc """
  Pure. The calendar a tracked title's stored payloads imply — what
  `MediaCentaur.TMDB.Store` holds becomes release rows here, never a
  request (ADR-071 §2).

    * `tv_releases/4` — the episodes after the library's last one, from
      the stored seasons; when no stored season yields any, the show's
      `next_episode_to_air` alone.
    * `movie_releases/1` — the film's US typed dates (theatrical,
      digital, physical), or its primary date as theatrical, each row
      carrying the film's own id as the part.
    * `season_sizes/3` — how many episodes each season has, keyed by
      season-number string, specials excluded: a stored season is sized
      by the episodes that aired on or before `today` (the count
      `Targeting.aired_counts/1` produces), any other by the show's
      `episode_count`, exact for a finished season. The drop planner
      hands this to every plan as its `span_sizes`, the fit denominator
      (`Acquisition.Plans.Fit`).
    * `seasons_wanted/2` — which seasons the calendar needs stored: the
      library's last season (at least the first) and the season the
      next episode airs in when that is later.
  """

  alias MediaCentaur.ReleaseTracking.Extractor
  alias MediaCentaur.TMDB.Mapper

  @type release :: %{
          required(:air_date) => Date.t() | nil,
          required(:title) => String.t() | nil,
          required(:season_number) => integer() | nil,
          required(:episode_number) => integer() | nil,
          optional(:release_type) => String.t(),
          optional(:part_tmdb_id) => integer()
        }

  @spec tv_releases(map(), [map()], non_neg_integer(), non_neg_integer()) :: [release()]
  def tv_releases(title_payload, season_payloads, last_season, last_episode) do
    releases =
      season_payloads
      |> Enum.filter(&is_list(&1["episodes"]))
      |> Enum.flat_map(&Extractor.extract_episodes_since(&1, last_season, last_episode))

    if releases == [], do: Extractor.extract_tv_releases(title_payload), else: releases
  end

  @spec movie_releases(map()) :: [release()]
  def movie_releases(payload) do
    payload
    |> Extractor.extract_movie_release_dates()
    |> Enum.map(fn release ->
      %{
        air_date: release.air_date,
        title: release.title,
        release_type: release.release_type,
        part_tmdb_id: payload["id"],
        season_number: nil,
        episode_number: nil
      }
    end)
  end

  # Specials (season 0) are extras, not coverage units — the exclusion
  # `Targeting.aired_counts/1` makes too.
  @spec season_sizes(map(), [map()], Date.t()) :: %{String.t() => non_neg_integer()}
  def season_sizes(title_payload, season_payloads, %Date{} = today) do
    stored = Map.new(season_payloads, &{&1["season_number"], &1})

    title_payload
    |> Map.get("seasons", [])
    |> List.wrap()
    |> Enum.filter(fn season ->
      is_integer(season["season_number"]) and season["season_number"] > 0
    end)
    |> Map.new(fn season ->
      number = season["season_number"]

      size =
        case Map.fetch(stored, number) do
          {:ok, %{"episodes" => episodes}} when is_list(episodes) -> aired_count(episodes, today)
          _not_stored -> season["episode_count"] || 0
        end

      {Integer.to_string(number), size}
    end)
  end

  @spec seasons_wanted(map(), non_neg_integer()) :: [pos_integer()]
  def seasons_wanted(title_payload, last_season) do
    base_season = max(last_season, 1)

    next_season =
      get_in(title_payload, ["next_episode_to_air", "season_number"]) ||
        title_payload["number_of_seasons"]

    if is_integer(next_season) and next_season > base_season,
      do: [base_season, next_season],
      else: [base_season]
  end

  defp aired_count(episodes, today) do
    Enum.count(episodes, fn episode ->
      case Mapper.parse_date(episode["air_date"]) do
        %Date{} = air_date -> Date.compare(air_date, today) != :gt
        nil -> false
      end
    end)
  end
end
