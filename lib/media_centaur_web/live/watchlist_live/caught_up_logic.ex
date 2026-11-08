defmodule MediaCentaurWeb.WatchlistLive.CaughtUpLogic do
  @moduledoc """
  The caught-up panel's pure logic (ADR-030): the `Panel` a Watchlist
  row opens from its state block, what each act does to it, and what
  *Set point* writes.

  The **caught-up point** is the latest aired episode the person has
  seen (`Watchlist.TitleIntent`); the row's *Caught up* button jumps it
  to TMDB's latest aired episode. The **caught-up panel** is for every
  other move — back a few episodes, back a season, to nothing — on a
  series of any length: a season select (every season newest first, each
  with its year and size, from the stored title's `seasons`) over the
  chosen season's episodes as chips, from the stored season
  (`TMDB.Store`); a season the store lacks is fetched when chosen
  (`episodes: :loading` until it lands, `:unavailable` when TMDB does
  not answer). A chip is a **selection**, not
  a write: *Set point* applies it through `ReleaseTracking.catch_up/2`;
  Cancel leaves the point. *Latest aired* and *Nothing yet* select
  without a chip.

  A chip's state (`chip/3`) reads the selection live, so the grid shows
  what Set point will mean: the selected episode is the `:point`; one at
  or before it, in the library (`Release.in_library`) or under the item's
  library watermark is `:had`; an aired one after it is `:out` (what Auto-grab
  will want); one TMDB has not aired is `:unaired` and cannot be selected.
  The library's word wins over TMDB's date — an episode the library holds
  is had even when TMDB dates it ahead.
  """

  alias MediaCentaur.Format
  alias MediaCentaur.ReleaseTracking.Calendar
  alias MediaCentaur.ReleaseTracking.Item, as: TrackingItem
  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaur.Watchlist.TitleIntent

  @typedoc "A season as the select lists it: its number, the year it began (nil when TMDB has no date) and how many episodes TMDB counts."
  @type season :: %{number: pos_integer(), year: pos_integer() | nil, count: non_neg_integer()}

  @typedoc "An episode as a chip: its number in the season, air date and name."
  @type episode :: %{number: pos_integer(), air_date: Date.t() | nil, name: String.t() | nil}

  @type selection :: TitleIntent.caught_up() | :none
  @type chip_state :: :point | :had | :out | :unaired

  defmodule Panel do
    @moduledoc """
    The caught-up panel's view-model: the row it belongs to (`ref`, `id`
    — the row's id with `-caught-up-panel`), the stored point and TMDB's
    latest aired pair, the seasons, the chosen `season` and its
    `episodes` (`:loading` until the store has it), the live `selection`
    (`:none` for no point), the library's say (`had`, the in-library
    pairs; `watermark`, the library's last episode) and whether the
    season list is open.
    """

    @enforce_keys [:ref, :id]
    defstruct [
      :ref,
      :id,
      :point,
      :latest,
      :season,
      seasons: [],
      episodes: :loading,
      selection: :none,
      had: MapSet.new(),
      watermark: {0, 0},
      menu_open?: false
    ]

    @type t :: %__MODULE__{
            ref: MediaCentaur.TMDB.Store.ref(),
            id: String.t(),
            point: TitleIntent.caught_up() | nil,
            latest: TitleIntent.caught_up() | nil,
            season: pos_integer() | nil,
            seasons: [MediaCentaurWeb.WatchlistLive.CaughtUpLogic.season()],
            episodes: [MediaCentaurWeb.WatchlistLive.CaughtUpLogic.episode()] | :loading | :unavailable,
            selection: MediaCentaurWeb.WatchlistLive.CaughtUpLogic.selection(),
            had: MapSet.t(TitleIntent.caught_up()),
            watermark: {non_neg_integer(), non_neg_integer()},
            menu_open?: boolean()
          }
  end

  @doc """
  The panel for a row: `row_id` and `ref` name it, `payload` is the
  stored title, `point` the record's caught-up pair (nil for none),
  `tracking` the item with its releases. It opens on the point's season
  — without a point, the latest aired episode's, else the newest — with
  the point selected and the episodes `:loading` until the page hands
  it the stored season (`season_loaded/3`).
  """
  @spec open(
          String.t(),
          MediaCentaur.TMDB.Store.ref(),
          map(),
          TitleIntent.caught_up() | nil,
          TrackingItem.t()
        ) ::
          Panel.t()
  def open(row_id, ref, payload, point, %TrackingItem{} = tracking) do
    seasons = seasons(payload)
    latest = Calendar.latest_aired(payload)

    season =
      case {point, latest, seasons} do
        {{season, _episode}, _latest, _seasons} -> season
        {nil, {season, _episode}, _seasons} -> season
        {nil, nil, [%{number: season} | _rest]} -> season
        {nil, nil, []} -> nil
      end

    %Panel{
      ref: ref,
      id: "#{row_id}-caught-up-panel",
      point: point,
      latest: latest,
      seasons: seasons,
      season: season,
      selection: point || :none,
      had: had(tracking),
      watermark: {tracking.last_library_season || 0, tracking.last_library_episode || 0}
    }
  end

  @doc "The seasons the select lists, newest first, specials (season 0) left out."
  @spec seasons(map()) :: [season()]
  def seasons(payload) do
    payload
    |> Map.get("seasons", [])
    |> List.wrap()
    |> Enum.filter(&(is_integer(&1["season_number"]) and &1["season_number"] >= 1))
    |> Enum.map(fn season ->
      %{
        number: season["season_number"],
        year: season["air_date"] |> Mapper.parse_date() |> year(),
        count: season["episode_count"] || 0
      }
    end)
    |> Enum.sort_by(& &1.number, :desc)
  end

  defp year(nil), do: nil
  defp year(%Date{year: year}), do: year

  @doc "A stored season's episodes as chips, in episode order; specials and unnumbered entries left out."
  @spec episodes(map()) :: [episode()]
  def episodes(season_payload) do
    season_payload
    |> Map.get("episodes", [])
    |> List.wrap()
    |> Enum.filter(&(is_integer(&1["episode_number"]) and &1["episode_number"] >= 1))
    |> Enum.map(
      &%{number: &1["episode_number"], air_date: Mapper.parse_date(&1["air_date"]), name: &1["name"]}
    )
    |> Enum.sort_by(& &1.number)
  end

  # Every in-library release as a pair — the library's half of *had*.
  defp had(%TrackingItem{releases: releases}) when is_list(releases) do
    for %{in_library: true, season_number: season, episode_number: episode} <- releases,
        is_integer(season) and is_integer(episode),
        into: MapSet.new(),
        do: {season, episode}
  end

  defp had(_tracking), do: MapSet.new()

  @doc "The select's words for a season: *Season 2 · 2025 · 8 episodes*; no year when TMDB has none."
  @spec season_label(season()) :: String.t()
  def season_label(%{number: number, year: year, count: count}) do
    [
      "Season #{number}",
      year && Integer.to_string(year),
      episodes_word(count)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp episodes_word(1), do: "1 episode"
  defp episodes_word(count), do: "#{count} episodes"

  @doc "Chooses a season: the list closes and the episodes are `:loading` until the store's season lands."
  @spec choose_season(Panel.t(), pos_integer()) :: Panel.t()
  def choose_season(%Panel{} = panel, season),
    do: %{panel | season: season, episodes: :loading, menu_open?: false}

  @doc "A stored season lands: its episodes, when it is still the chosen season; otherwise nothing changes."
  @spec season_loaded(Panel.t(), pos_integer(), map()) :: Panel.t()
  def season_loaded(%Panel{season: season} = panel, season, season_payload),
    do: %{panel | episodes: episodes(season_payload)}

  def season_loaded(%Panel{} = panel, _other_season, _season_payload), do: panel

  @doc "TMDB did not answer for the chosen season: the panel says so instead of a grid."
  @spec season_failed(Panel.t(), pos_integer()) :: Panel.t()
  def season_failed(%Panel{season: season} = panel, season), do: %{panel | episodes: :unavailable}
  def season_failed(%Panel{} = panel, _other_season), do: panel

  @doc "Selects an episode (a chip press)."
  @spec pick(Panel.t(), TitleIntent.caught_up()) :: Panel.t()
  def pick(%Panel{} = panel, {_season, _episode} = pair), do: %{panel | selection: pair}

  @doc "Selects TMDB's latest aired episode; nothing changes when TMDB has aired none."
  @spec latest(Panel.t()) :: Panel.t()
  def latest(%Panel{latest: nil} = panel), do: panel
  def latest(%Panel{latest: latest} = panel), do: %{panel | selection: latest}

  @doc "Selects no point at all: the person has seen nothing yet."
  @spec nothing(Panel.t()) :: Panel.t()
  def nothing(%Panel{} = panel), do: %{panel | selection: :none}

  @doc """
  What *Set point* writes: `{:set, pair}` for a selected episode,
  `:clear` for Nothing yet, `:unchanged` when the selection is the point
  as it stands.
  """
  @spec change(Panel.t()) :: {:set, TitleIntent.caught_up()} | :clear | :unchanged
  def change(%Panel{point: point, selection: point}), do: :unchanged
  def change(%Panel{point: nil, selection: :none}), do: :unchanged
  def change(%Panel{selection: :none}), do: :clear
  def change(%Panel{selection: {_season, _episode} = pair}), do: {:set, pair}

  @doc "The selection as the panel's readout says it: *S02E05*, or *Nothing yet*."
  @spec selection_words(Panel.t()) :: String.t()
  def selection_words(%Panel{selection: :none}), do: "Nothing yet"
  def selection_words(%Panel{selection: {season, episode}}), do: Format.episode_label(season, episode)

  @doc "An episode chip's state in the chosen season, read against the live selection (see the moduledoc)."
  @spec chip(Panel.t(), episode(), Date.t()) :: chip_state()
  def chip(%Panel{season: season} = panel, %{number: number, air_date: air_date}, %Date{} = today) do
    pair = {season, number}

    cond do
      pair == panel.selection -> :point
      had?(panel, pair) -> :had
      is_nil(air_date) or Date.after?(air_date, today) -> :unaired
      true -> :out
    end
  end

  defp had?(%Panel{selection: selection, had: had, watermark: watermark}, pair) do
    MapSet.member?(had, pair) or pair <= watermark or (selection != :none and pair <= selection)
  end
end
