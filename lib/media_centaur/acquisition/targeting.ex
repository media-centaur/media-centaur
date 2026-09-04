defmodule MediaCentaur.Acquisition.Targeting do
  @moduledoc """
  The targeting (Select) phase of media search: enumerates a TMDB
  series into the unit universe a plan can want — every aired episode,
  annotated with what the library already has and whether release
  tracking covers the series. Subtractions are **shown, not silent**
  (campaign decision 2026-06-09): the picker greys out owned units
  rather than hiding them.

  Specials (season 0) are excluded — they're extras, not coverage
  units. Unaired episodes are enumerated but flagged `aired?: false`;
  media search is bounded to what exists now (the future is release
  tracking's job).

  Read-only: TMDB + Library + ReleaseTracking lookups, no writes.
  """

  alias MediaCentaur.Library
  alias MediaCentaur.ReleaseTracking
  alias MediaCentaur.TMDB

  defmodule Episode do
    @moduledoc """
    One unit of the targeting universe — an episode with its
    pickability facts. `tracked?` means release tracking holds an open
    want for the unit *and* the item's effective auto-grab mode
    actually grabs (ADR-056 Q3: with mode off, media search is the
    expected path, so nothing is marked). Tracked units stay pickable —
    subtraction is shown, never silent — but the presets skip them.
    """

    @enforce_keys [:season_number, :episode_number, :label, :aired?, :in_library?]
    defstruct [
      :season_number,
      :episode_number,
      :label,
      :air_date,
      :aired?,
      :in_library?,
      tracked?: false
    ]

    @type t :: %__MODULE__{
            season_number: pos_integer(),
            episode_number: pos_integer(),
            label: String.t(),
            air_date: Date.t() | nil,
            aired?: boolean(),
            in_library?: boolean(),
            tracked?: boolean()
          }
  end

  defmodule Season do
    @moduledoc "One season row of the picker: its episodes in order."

    @enforce_keys [:season_number, :episodes]
    defstruct [:season_number, :episodes]

    @type t :: %__MODULE__{season_number: pos_integer(), episodes: [Episode.t()]}
  end

  defmodule Selection do
    @moduledoc """
    The full targeting universe for one series. `backdrop_path` /
    `logo_path` are raw TMDB paths (the `get_tv` detail rides images
    along) so the plan modal can wear the series' cinematic identity —
    the same dress the movie fast path gets from its preview.
    """

    @enforce_keys [:tmdb_id, :title, :seasons, :tracked?]
    defstruct [
      :tmdb_id,
      :title,
      :poster_path,
      :backdrop_path,
      :logo_path,
      :seasons,
      :tracked?,
      origin_country: []
    ]

    @type t :: %__MODULE__{
            tmdb_id: String.t(),
            title: String.t(),
            poster_path: String.t() | nil,
            backdrop_path: String.t() | nil,
            logo_path: String.t() | nil,
            seasons: [Season.t()],
            tracked?: boolean(),
            origin_country: [String.t()]
          }
  end

  @doc """
  Enumerates the series' targeting universe: per-season aired/unaired
  episodes with library presence, plus the series-level tracked flag.
  One `get_tv` plus one `get_season` per real season.
  """
  @spec series_selection(String.t() | integer(), Req.Request.t() | nil) ::
          {:ok, Selection.t()} | {:error, term()}
  def series_selection(tmdb_id, client \\ nil) do
    tmdb_id = to_string(tmdb_id)
    client = client || TMDB.Client.default_client()

    with {:ok, tv} <- TMDB.Client.get_tv(tmdb_id, client: client),
         {:ok, seasons} <- load_seasons(tmdb_id, tv, client) do
      {:ok,
       %Selection{
         tmdb_id: tmdb_id,
         title: tv["name"],
         poster_path: tv["poster_path"],
         backdrop_path: tv["backdrop_path"],
         logo_path: TMDB.Mapper.pick_logo_path(tv),
         seasons: seasons,
         tracked?: tracked?(tmdb_id),
         origin_country: tv["origin_country"] || []
       }}
    end
  end

  @doc """
  The design-session default: **everything aired, minus what the
  library already has, minus what release tracking is already wanting**
  (ADR-056) — as `{season, episode}` units in airing order. Tracked
  units stay visible and pickable in the picker; they just aren't
  pre-chosen, since the cadence is already on them.
  """
  @spec default_units(Selection.t()) :: [{pos_integer(), pos_integer()}]
  def default_units(%Selection{seasons: seasons}) do
    for season <- seasons,
        episode <- season.episodes,
        episode.aired? and not episode.in_library? and not episode.tracked?,
        do: {episode.season_number, episode.episode_number}
  end

  @doc """
  Per-season aired-episode counts, keyed by season-number string
  (`%{"1" => 24, "2" => 18}`) — the planner's fit denominator. Only
  aired episodes count: a season pack lands what has actually been
  released, so unaired episodes don't inflate the span. Persisted on the
  plan at creation so `RunPlan` needs no second TMDB fetch.
  """
  @spec aired_counts(Selection.t()) :: %{String.t() => non_neg_integer()}
  def aired_counts(%Selection{seasons: seasons}) do
    for season <- seasons, into: %{} do
      aired = Enum.count(season.episodes, & &1.aired?)
      {Integer.to_string(season.season_number), aired}
    end
  end

  defp load_seasons(tmdb_id, tv, client) do
    today = Date.utc_today()
    tracked_units = tracked_want_units(tmdb_id)

    tv
    |> Map.get("seasons", [])
    |> Enum.map(& &1["season_number"])
    |> Enum.filter(&(is_integer(&1) and &1 > 0))
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn season_number, {:ok, seasons} ->
      case TMDB.Client.get_season(tmdb_id, season_number, client: client) do
        {:ok, season_data} ->
          {:cont,
           {:ok, [build_season(tmdb_id, season_number, season_data, today, tracked_units) | seasons]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, seasons} -> {:ok, Enum.reverse(seasons)}
      error -> error
    end
  end

  defp build_season(tmdb_id, season_number, season_data, today, tracked_units) do
    episodes =
      season_data
      |> Map.get("episodes", [])
      |> Enum.map(fn episode_data ->
        episode_number = episode_data["episode_number"]
        air_date = TMDB.Mapper.parse_date(episode_data["air_date"])

        %Episode{
          season_number: season_number,
          episode_number: episode_number,
          label: episode_data["name"] || "Episode #{episode_number}",
          air_date: air_date,
          aired?: aired?(air_date, today),
          in_library?: in_library?(tmdb_id, season_number, episode_number),
          tracked?: MapSet.member?(tracked_units, {season_number, episode_number})
        }
      end)

    %Season{season_number: season_number, episodes: episodes}
  end

  # Open wants of the title's tracking item, as a `{season, episode}`
  # set — empty when untracked or when the effective auto-grab mode is
  # off (nothing is going to grab them, so media search shouldn't
  # subtract them).
  defp tracked_want_units(tmdb_id) do
    with {numeric_id, ""} <- Integer.parse(tmdb_id),
         %{} = item <- ReleaseTracking.get_item_by_tmdb(numeric_id, :tv_series),
         mode when mode != "off" <-
           MediaCentaur.Acquisition.AutoGrabSettings.effective_mode(
             item.auto_grab_mode,
             MediaCentaur.Acquisition.AutoGrabSettings.load()
           ) do
      item.id
      |> ReleaseTracking.open_wants_for_item()
      |> Enum.map(&{&1.season_number, &1.episode_number})
      |> Enum.reject(&(&1 == {nil, nil}))
      |> MapSet.new()
    else
      _ -> MapSet.new()
    end
  end

  defp aired?(nil, _today), do: false
  defp aired?(%Date{} = air_date, today), do: Date.compare(air_date, today) != :gt

  defp in_library?(tmdb_id, season_number, episode_number) do
    case Library.ExternalIds.find_present_episode(tmdb_id, season_number, episode_number) do
      {:ok, _path} -> true
      :not_found -> false
    end
  end

  defp tracked?(tmdb_id) do
    case Integer.parse(tmdb_id) do
      {numeric_id, ""} -> ReleaseTracking.get_item_by_tmdb(numeric_id, :tv_series) != nil
      _ -> false
    end
  end
end
