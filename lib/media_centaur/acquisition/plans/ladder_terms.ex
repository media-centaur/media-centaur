defmodule MediaCentaur.Acquisition.Plans.LadderTerms do
  @moduledoc """
  The coverage ladder's search terms — single source of truth shared by
  the plan runner (all wanted units) and the alternatives picker (one
  unit), so the two can never drift on what "this plan's searches"
  means.

  TV terms run broad-to-narrow: the series title, `Title Season N` +
  `Title SNN` per season, `Title SNNENN` per episode. Movies are one
  term (`Title [year]`). All terms pair with the Prowlarr `type` opt —
  the corpus keys on term + type.
  """

  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}

  @type term_pair :: {String.t(), keyword()}

  @doc "Every ladder term for the plan's wanted `{season, episode}` units."
  @spec for_plan(Plan.t(), [{pos_integer(), pos_integer()}]) :: [term_pair()]
  def for_plan(%Plan{tmdb_type: "movie"} = plan, _wanted), do: [movie_term(plan)]

  def for_plan(%Plan{tmdb_type: "tv"} = plan, wanted) do
    seasons = wanted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()

    series_terms = [{plan.title, [type: :tv]}]

    season_terms =
      Enum.flat_map(seasons, fn season ->
        [
          {"#{plan.title} Season #{season}", [type: :tv]},
          {"#{plan.title} S#{pad(season)}", [type: :tv]}
        ]
      end)

    episode_terms =
      Enum.map(wanted, fn {season, episode} ->
        {"#{plan.title} S#{pad(season)}E#{pad(episode)}", [type: :tv]}
      end)

    series_terms ++ season_terms ++ episode_terms
  end

  @doc "The ladder terms that can cover ONE unit: series, its season, its episode."
  @spec for_unit(Plan.t(), PlanUnit.t()) :: [term_pair()]
  def for_unit(%Plan{tmdb_type: "movie"} = plan, %PlanUnit{}), do: [movie_term(plan)]

  def for_unit(%Plan{tmdb_type: "tv"} = plan, %PlanUnit{} = unit) do
    for_plan(plan, [{unit.season_number, unit.episode_number}])
  end

  defp movie_term(plan) do
    term = if plan.year, do: "#{plan.title} #{plan.year}", else: plan.title
    {term, [type: :movie]}
  end

  defp pad(number), do: number |> Integer.to_string() |> String.pad_leading(2, "0")
end
