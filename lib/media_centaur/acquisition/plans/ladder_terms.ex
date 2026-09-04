defmodule MediaCentaur.Acquisition.Plans.LadderTerms do
  @moduledoc """
  The coverage ladder's search terms — single source of truth shared by
  the plan runner (rung by rung, via `series_terms/1` / `season_terms/2`
  / `episode_terms/2`), the alternatives picker (one unit), and the
  corpus keys, so none of them can drift on what "this plan's searches"
  means. `for_plan/2` is exactly the rung constructors concatenated —
  an invariant pinned by the test suite.

  TV terms run broad-to-narrow: the series title, `Title Season N` +
  `Title SNN` per season, `Title SNNENN` per episode. Movies run
  precise-to-broad: `Title year`, then the year-less `Title` (release
  years drift — festival premiere vs theatrical). Every title is
  sanitized via `Search.QueryTerm` (scene names carry no apostrophes).
  All terms pair with the Prowlarr `type` opt — the corpus keys on
  term + type.
  """

  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Format
  alias MediaCentaur.Search.QueryTerm

  @type search_term :: String.t()

  @doc "Every ladder term for the plan's wanted `{season, episode}` units."
  @spec for_plan(Plan.t(), [{pos_integer(), pos_integer()}]) :: [search_term()]
  def for_plan(%Plan{tmdb_type: "movie"} = plan, _wanted), do: movie_terms(plan)

  def for_plan(%Plan{tmdb_type: "tv"} = plan, wanted) do
    seasons = wanted |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
    series_terms(plan) ++ season_terms(plan, seasons) ++ episode_terms(plan, wanted)
  end

  @doc "The broadest rung — one term for an all-in-one release."
  @spec series_terms(Plan.t()) :: [search_term()]
  def series_terms(%Plan{tmdb_type: "tv"} = plan), do: [title(plan)]

  @doc """
  The season rung — both text forms per season, broad-to-narrow within the rung.

  Expects unique, ascending seasons (the residual derivation provides this).
  """
  @spec season_terms(Plan.t(), [pos_integer()]) :: [search_term()]
  def season_terms(%Plan{tmdb_type: "tv"} = plan, seasons) do
    Enum.flat_map(seasons, fn season ->
      ["#{title(plan)} Season #{season}", "#{title(plan)} S#{Format.pad2(season)}"]
    end)
  end

  @doc "The episode rung — one term per `{season, episode}` unit."
  @spec episode_terms(Plan.t(), [{pos_integer(), pos_integer()}]) :: [search_term()]
  def episode_terms(%Plan{tmdb_type: "tv"} = plan, units) do
    Enum.map(units, fn {season, episode} ->
      "#{title(plan)} #{Format.episode_label(season, episode)}"
    end)
  end

  @doc "The ladder terms that can cover ONE unit: series, its season, its episode."
  @spec for_unit(Plan.t(), PlanUnit.t()) :: [search_term()]
  def for_unit(%Plan{tmdb_type: "movie"} = plan, %PlanUnit{}), do: movie_terms(plan)

  def for_unit(%Plan{tmdb_type: "tv"} = plan, %PlanUnit{} = unit) do
    for_plan(plan, [{unit.season_number, unit.episode_number}])
  end

  @doc """
  The movie rungs, precise-to-broad: `Title year`, then the year-less
  `Title`. Release names carry whichever year the group's source used
  (festival premiere vs theatrical), so the year term alone can miss
  every release of the right movie. No year → one term.
  """
  @spec movie_terms(Plan.t()) :: [search_term()]
  def movie_terms(%Plan{tmdb_type: "movie", year: nil} = plan), do: [title(plan)]

  def movie_terms(%Plan{tmdb_type: "movie"} = plan) do
    ["#{title(plan)} #{plan.year}", title(plan)]
  end

  defp title(plan), do: QueryTerm.sanitize(plan.title)
end
