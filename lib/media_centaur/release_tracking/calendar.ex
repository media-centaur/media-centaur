defmodule MediaCentaur.ReleaseTracking.Calendar do
  @moduledoc """
  Pure. The calendar a tracked title's stored payloads imply — what
  `MediaCentaur.TMDB.Store` holds becomes release rows here, never a
  request (ADR-071 §2).

    * `tv_releases/3` — the episodes after the have-point
      (`ReleaseTracking.Had.point/2`: the later of the library's last
      episode and the person's caught-up point), from the stored
      seasons; when no stored season yields any, the show's
      `next_episode_to_air` alone.
    * `read/3` — what a followed series' calendar says right now: the
      aired releases not had (**out**) and the date of the next one
      ahead (**next**). The Watchlist page's state and Discovery's Out
      Now placement read a series through this one function (M16).
    * `latest_aired/1` — TMDB's latest aired episode from the stored
      payload (`last_episode_to_air`), as a pair: what Follow and the
      *Caught up* press set the point to, and what the finish prompt
      compares a completed episode against.
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
      have-point's season (at least the first) and the season the next
      episode airs in when that is later. Nothing between the two: a
      point two seasons behind the one airing leaves the season between
      unfetched, the same gap the library watermark has always had.
  """

  alias MediaCentaur.ReleaseTracking.{Extractor, Had, Item, Release}
  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaur.Watchlist.TitleIntent

  @type release :: %{
          required(:air_date) => Date.t() | nil,
          required(:title) => String.t() | nil,
          required(:season_number) => integer() | nil,
          required(:episode_number) => integer() | nil,
          optional(:release_type) => String.t(),
          optional(:part_tmdb_id) => integer()
        }

  @spec tv_releases(map(), [map()], Had.point()) :: [release()]
  def tv_releases(title_payload, season_payloads, {last_season, last_episode}) do
    releases =
      season_payloads
      |> Enum.filter(&is_list(&1["episodes"]))
      |> Enum.flat_map(&Extractor.extract_episodes_since(&1, last_season, last_episode))

    if releases == [], do: Extractor.extract_tv_releases(title_payload), else: releases
  end

  @typedoc "A series' calendar read: the aired releases not had, oldest first, and the next release dated ahead."
  @type reading :: %{out: [Release.t()], next: Release.t() | nil}

  @doc """
  What a followed series' calendar says at `today`, given the person's
  caught-up point: `out`, the aired releases not had, oldest first; and
  `next`, the release with the nearest air date after today (the lowest
  episode on that date), nil when nothing is dated.
  The item carries its releases and its library watermark.
  """
  @spec read(Item.t(), TitleIntent.caught_up() | nil, Date.t()) :: reading()
  def read(%Item{releases: releases} = item, caught_up, %Date{} = today) when is_list(releases) do
    point = Had.point(item, caught_up)

    out =
      releases
      |> Enum.filter(&(Release.released?(&1, today) and not Had.had?(&1, point)))
      |> in_air_order()

    next =
      releases
      |> Enum.filter(&(&1.air_date != nil and Date.after?(&1.air_date, today)))
      |> in_air_order()
      |> List.first()

    %{out: out, next: next}
  end

  defp in_air_order(releases),
    do:
      Enum.sort_by(
        releases,
        &{&1.air_date, &1.season_number, &1.episode_number},
        &compare_release_keys/2
      )

  defp compare_release_keys({date_a, season_a, episode_a}, {date_b, season_b, episode_b}) do
    case Date.compare(date_a, date_b) do
      :eq -> {season_a, episode_a} <= {season_b, episode_b}
      :lt -> true
      :gt -> false
    end
  end

  @doc "TMDB's latest aired episode from a series payload, as `{season_number, episode_number}`; nil without one."
  @spec latest_aired(map()) :: TitleIntent.caught_up() | nil
  def latest_aired(%{"last_episode_to_air" => %{"season_number" => season, "episode_number" => episode}})
      when is_integer(season) and is_integer(episode) and season >= 1 and episode >= 1,
      do: {season, episode}

  def latest_aired(_payload), do: nil

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
