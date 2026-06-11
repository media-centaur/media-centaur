defmodule MediaCentaurWeb.AcquisitionLive.PlanLogic do
  @moduledoc """
  Pure selection logic for the targeting picker (UIDR-014, ADR-030):
  the chosen-units set, season tri-states, and the quick-action
  presets. The LiveView holds a `MapSet` of `{season, episode}` tuples;
  every function here maps `(selection, chosen)` to a new `chosen` or a
  derived display fact. Checkbox state is the single source of truth —
  presets only write into it.

  Only **pickable** units participate: aired and not already in the
  library (in-library rows render greyed; unaired rows render inert —
  subtractions shown, never silently applied).
  """

  alias MediaCentaur.Acquisition.Targeting

  @type unit :: {pos_integer(), pos_integer()}

  @doc "All pickable `{season, episode}` units of a selection."
  @spec pickable_units(Targeting.Selection.t()) :: [unit()]
  def pickable_units(%Targeting.Selection{seasons: seasons}) do
    for season <- seasons,
        episode <- season.episodes,
        episode.aired? and not episode.in_library?,
        do: {episode.season_number, episode.episode_number}
  end

  @doc "The pickable units of one season."
  @spec pickable_units(Targeting.Selection.t(), pos_integer()) :: [unit()]
  def pickable_units(%Targeting.Selection{} = selection, season_number) do
    selection
    |> pickable_units()
    |> Enum.filter(fn {season, _episode} -> season == season_number end)
  end

  @doc "Toggles one unit in the chosen set (no-op for unpickable units)."
  @spec toggle_unit(MapSet.t(), Targeting.Selection.t(), unit()) :: MapSet.t()
  def toggle_unit(chosen, %Targeting.Selection{} = selection, unit) do
    cond do
      unit not in pickable_units(selection) -> chosen
      MapSet.member?(chosen, unit) -> MapSet.delete(chosen, unit)
      true -> MapSet.put(chosen, unit)
    end
  end

  @doc """
  Toggles a whole season: any pickable unit unchosen → choose them all;
  all chosen → clear the season.
  """
  @spec toggle_season(MapSet.t(), Targeting.Selection.t(), pos_integer()) :: MapSet.t()
  def toggle_season(chosen, %Targeting.Selection{} = selection, season_number) do
    season_units = pickable_units(selection, season_number)

    if Enum.all?(season_units, &MapSet.member?(chosen, &1)) do
      Enum.reduce(season_units, chosen, &MapSet.delete(&2, &1))
    else
      Enum.reduce(season_units, chosen, &MapSet.put(&2, &1))
    end
  end

  @doc """
  The season checkbox's display state: `:checked` (every pickable unit
  chosen, and there are some), `:indeterminate` (some chosen, or all
  chosen but unpickable rows exist in the season — the subtraction
  stays visible), `:unchecked`, or `:disabled` (nothing pickable).
  """
  @spec season_state(MapSet.t(), Targeting.Selection.t(), Targeting.Season.t()) ::
          :checked | :indeterminate | :unchecked | :disabled
  def season_state(chosen, %Targeting.Selection{} = selection, %Targeting.Season{} = season) do
    season_units = pickable_units(selection, season.season_number)
    chosen_count = Enum.count(season_units, &MapSet.member?(chosen, &1))
    unpickable? = length(season.episodes) > length(season_units)

    cond do
      season_units == [] -> :disabled
      chosen_count == 0 -> :unchecked
      chosen_count < length(season_units) -> :indeterminate
      unpickable? -> :indeterminate
      true -> :checked
    end
  end

  @doc """
  Quick-action presets writing into the chosen set:

  * `:everything_aired` — the design default: every pickable unit
    minus tracked wants (`Targeting.default_units/1` — release
    tracking is already on those; ADR-056).
  * `:continue` — default units strictly after the library's last
    present episode (everything when the library has none).
  * `:latest_season` — the default units of the last season that has
    any.

  Presets skip tracked units; the units themselves stay pickable —
  checking one is the user's explicit override.
  """
  @spec apply_preset(Targeting.Selection.t(), :everything_aired | :continue | :latest_season) ::
          MapSet.t()
  def apply_preset(%Targeting.Selection{} = selection, :everything_aired) do
    selection |> Targeting.default_units() |> MapSet.new()
  end

  def apply_preset(%Targeting.Selection{} = selection, :continue) do
    last_owned =
      for season <- selection.seasons,
          episode <- season.episodes,
          episode.in_library?,
          reduce: nil do
        acc -> max_unit(acc, {episode.season_number, episode.episode_number})
      end

    selection
    |> Targeting.default_units()
    |> Enum.filter(fn unit -> last_owned == nil or unit > last_owned end)
    |> MapSet.new()
  end

  def apply_preset(%Targeting.Selection{} = selection, :latest_season) do
    default_units = MapSet.new(Targeting.default_units(selection))

    selection.seasons
    |> Enum.map(& &1.season_number)
    |> Enum.sort(:desc)
    |> Enum.find_value(MapSet.new(), fn season_number ->
      units =
        selection
        |> pickable_units(season_number)
        |> Enum.filter(&MapSet.member?(default_units, &1))

      case units do
        [] -> nil
        units -> MapSet.new(units)
      end
    end)
  end

  defp max_unit(nil, unit), do: unit
  defp max_unit(acc, unit) when unit > acc, do: unit
  defp max_unit(acc, _unit), do: acc

  @doc """
  Toggles one season in the picker's expanded-seasons set. Seasons
  start collapsed — the set holds only the season numbers the user has
  opened.
  """
  @spec toggle_expanded(MapSet.t(), pos_integer()) :: MapSet.t()
  def toggle_expanded(expanded, season_number) do
    if MapSet.member?(expanded, season_number) do
      MapSet.delete(expanded, season_number)
    else
      MapSet.put(expanded, season_number)
    end
  end

  @doc "Chosen units in airing order — the shape `Plans.create_series_plan/3` takes."
  @spec chosen_in_order(MapSet.t(), Targeting.Selection.t()) :: [unit()]
  def chosen_in_order(chosen, %Targeting.Selection{} = selection) do
    selection
    |> pickable_units()
    |> Enum.filter(&MapSet.member?(chosen, &1))
  end

  @doc """
  Chunks a season row's cells into render runs for the coverage grid:
  consecutive `:assigned` cells sharing one release fuse into a
  `{:capsule, guid, cells}` (the consolidation visual — one pack, one
  outline); everything else renders as `{:cell, cell}` singles.
  """
  @spec cell_runs([struct()]) :: [{:capsule, String.t(), [struct()]} | {:cell, struct()}]
  def cell_runs(cells) do
    cells
    |> Enum.chunk_by(fn cell ->
      if cell.state == :assigned, do: {:assigned, cell.release_guid}, else: :single
    end)
    |> Enum.flat_map(fn
      [%{state: :assigned, release_guid: guid} | _rest] = run when length(run) > 1 ->
        [{:capsule, guid, run}]

      run ->
        Enum.map(run, &{:cell, &1})
    end)
  end

  @doc """
  Maps a raw TMDB movie payload into the movie-confirm stage's display
  facts — everything on hand that helps the user verify the result is
  the title they meant: overview, human runtime, genre line. Absent or
  blank TMDB fields become `nil` so the template can drop them.
  """
  @spec movie_facts(map(), boolean()) :: map()
  def movie_facts(tmdb_movie, in_library?) do
    %{
      tmdb_id: to_string(tmdb_movie["id"]),
      title: tmdb_movie["title"],
      year: extract_year(tmdb_movie["release_date"]),
      overview: presence(tmdb_movie["overview"]),
      runtime: format_runtime(tmdb_movie["runtime"]),
      genres: format_genres(tmdb_movie["genres"]),
      poster_path: tmdb_movie["poster_path"],
      in_library?: in_library?
    }
  end

  defp extract_year(<<year::binary-size(4), _rest::binary>>), do: String.to_integer(year)
  defp extract_year(_release_date), do: nil

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_value), do: nil

  defp format_runtime(minutes) when is_integer(minutes) and minutes > 0,
    do: MediaCentaurWeb.LibraryFormatters.format_human_duration(minutes * 60)

  defp format_runtime(_minutes), do: nil

  defp format_genres([_ | _] = genres), do: Enum.map_join(genres, " · ", & &1["name"])
  defp format_genres(_genres), do: nil
end
