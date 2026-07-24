defmodule MediaCentaurWeb.IncomingLive.PlanLogic do
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
  alias MediaCentaur.Library.Person
  alias MediaCentaur.TMDB.Mapper
  alias MediaCentaurWeb.IncomingLive.MoviePreview
  alias MediaCentaurWeb.Components.Detail.Logic, as: DetailLogic

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
  Builds the `:movie_confirm` stage's detail-shaped preview from a raw
  TMDB movie payload.

  Derivation reuses `TMDB.Mapper.movie_attrs/3` (the exact mapping the
  import pipeline runs) and `Mapper.image_list/1` for absolute artwork
  URLs, so the preview can never drift from what ingestion would record.
  Facets are assembled by the same `Detail.Logic.facets_for/2` the owned
  movie detail panel uses; cast becomes `Library.Person` structs capped
  to the top billing. Absent/blank fields collapse to `nil`/empty.
  """
  @spec movie_preview(map(), boolean()) :: MoviePreview.t()
  def movie_preview(tmdb_movie, in_library?) do
    tmdb_id = tmdb_movie["id"]
    attrs = Mapper.movie_attrs(tmdb_id, tmdb_movie, nil)
    images = Map.new(Mapper.image_list(tmdb_movie), &{&1.role, &1.url})

    %MoviePreview{
      tmdb_id: to_string(tmdb_id),
      title: attrs.name,
      year: attrs.date_published && attrs.date_published.year,
      tagline: attrs.tagline,
      overview: presence(attrs.description),
      backdrop_url: images["backdrop"],
      logo_url: images["logo"],
      poster_url: images["poster"],
      metadata_items: movie_metadata_items(attrs),
      facets: DetailLogic.facets_for(:movie, attrs),
      cast: movie_cast(attrs.cast),
      in_library?: in_library?
    }
  end

  # Non-facet row items: year and runtime plus certification and country,
  # mirroring the owned detail panel's metadata row. Rating, director,
  # language, studio, and genres live in the facet strip, never here.
  defp movie_metadata_items(attrs) do
    Enum.reject(
      [
        DetailLogic.year_from_date(attrs.date_published),
        runtime_label(attrs.duration_seconds),
        attrs.content_rating,
        attrs.country_code
      ],
      &(is_nil(&1) or &1 == "")
    )
  end

  defp runtime_label(seconds) when is_integer(seconds) and seconds > 0,
    do: MediaCentaurWeb.LibraryFormatters.format_human_duration(seconds)

  defp runtime_label(_seconds), do: nil

  # The top-billed few — a compact confirmation strip, not the full
  # detail-panel cast grid. Mapper already sorts by billing order.
  @cast_preview_limit 10
  defp movie_cast(cast) when is_list(cast) do
    cast
    |> Enum.take(@cast_preview_limit)
    |> Enum.map(fn person ->
      %Person{
        name: person["name"],
        character: person["character"],
        profile_path: person["profile_path"],
        tmdb_person_id: person["tmdb_person_id"],
        order: person["order"]
      }
    end)
  end

  defp movie_cast(_cast), do: []

  defp presence(value) when is_binary(value) and value != "", do: value
  defp presence(_value), do: nil
end
