defmodule MediaCentaur.Acquisition.Plans.SearchOrder do
  @moduledoc """
  The order a TV plan searches its scopes, decided by fit (spec
  `docs/superpowers/specs/2026-09-17-planning-descent-design.md`):
  search the scopes whose pack could be assigned, widest first; then,
  only for units still unfound, the remaining scopes narrowest first,
  as offers.

  A scope *fits* when a pack at that scope could clear the fit gate for
  some span of the want (`Fit`) — the series when the whole want is
  most of the show, a season when the want is most of that season; the
  episode scope always fits. Those are the `:primary` steps, and the
  runner halts as soon as the residual empties, so a one-episode want
  that finds its single makes one indexer request. The `:fallback`
  steps are the scopes that did not fit, narrowest first: every pack
  they surface fails the fit gate by construction and lands as an offer
  (`Planner`), never an assignment — though an episode-scoped single a
  wider term happens to return can still be assigned.

  When fit cannot be judged — no span sizes, or no threshold, which is
  every movie and a tracking-born plan whose item has no season sizes
  yet — every scope fits and the order is widest first with no
  fallback: the search as it was before this module.

  Each step carries `terms/1`, a function of the current residual, so
  the runner spends only the terms the residual justifies; a step whose
  terms come back empty is skipped. A step that could never yield a
  term for this want is not returned at all. The strings come from
  `Search.SearchTerms`, the one place a term is spelled, through the
  plan's identity criteria (`MatchCriteria`). Pure — no I/O, no DB.
  """

  alias MediaCentaur.Acquisition.Plans.{Fit, MatchCriteria, Plan, PlanUnit}
  alias MediaCentaur.Search.{Criteria, ReleaseCoverage, SearchTerms}

  @type scope :: :series | :season | :episode
  @type kind :: :primary | :fallback

  @type step :: %{
          scope: scope(),
          kind: kind(),
          terms: ([ReleaseCoverage.unit()] -> [SearchTerms.search_term()])
        }

  @typedoc "The fit inputs: the plan's span sizes and the pack threshold as a fraction (nil = not judged)."
  @type prefs :: %{
          optional(:span_sizes) => Fit.span_sizes(),
          optional(:pack_min_fit) => number() | nil
        }

  @doc """
  The Prowlarr/corpus options every one of this plan's terms is searched
  with (`Search.SearchTerms.search_opts/1` for the plan's identity).
  Part of the corpus key: the plan runner, the alternatives picker and
  the commit path must all pass these when addressing a plan's terms.
  """
  @spec search_opts(Plan.t()) :: keyword()
  def search_opts(%Plan{} = plan), do: plan |> MatchCriteria.from() |> SearchTerms.search_opts()

  @doc "The ordered steps for a TV plan's want."
  @spec steps(Plan.t(), [ReleaseCoverage.unit()], prefs()) :: [step()]
  def steps(%Plan{tmdb_type: "tv"} = plan, wanted, prefs) do
    criteria = MatchCriteria.from(plan)
    threshold = Map.get(prefs, :pack_min_fit)
    span_sizes = Map.get(prefs, :span_sizes, %{})

    series_fits? = Fit.fits?(length(wanted), Fit.span_total(:series, span_sizes), threshold)

    {fitting_seasons, other_seasons} =
      wanted
      |> seasons()
      |> Enum.split_with(&season_fits?(&1, wanted, span_sizes, threshold))

    primary = [
      series_step(criteria, :primary, series_fits?),
      season_step(criteria, :primary, fitting_seasons),
      %{scope: :episode, kind: :primary, terms: &SearchTerms.episode_terms(criteria, &1)}
    ]

    fallback = [
      season_step(criteria, :fallback, other_seasons),
      series_step(criteria, :fallback, not series_fits?)
    ]

    Enum.reject(primary ++ fallback, &is_nil/1)
  end

  @doc """
  Every term for a want in search order — the primary steps, then the
  fallback ones, each taken against the whole want. What the swap
  picker and the gap evidence enumerate, so they read the corpus in
  the order the run filled it. Movie terms have no scope and come
  straight from `SearchTerms`.
  """
  @spec terms(Plan.t(), [ReleaseCoverage.unit()], prefs()) :: [SearchTerms.search_term()]
  def terms(%Plan{tmdb_type: "movie"} = plan, _wanted, _prefs),
    do: plan |> MatchCriteria.from() |> SearchTerms.movie_terms()

  def terms(%Plan{tmdb_type: "tv"} = plan, wanted, prefs) do
    plan
    |> steps(wanted, prefs)
    |> Enum.flat_map(& &1.terms.(wanted))
  end

  @doc "`terms/3` for one plan unit's own want."
  @spec terms_for_unit(Plan.t(), PlanUnit.t(), prefs()) :: [SearchTerms.search_term()]
  def terms_for_unit(%Plan{tmdb_type: "movie"} = plan, %PlanUnit{}, prefs), do: terms(plan, [], prefs)

  def terms_for_unit(%Plan{tmdb_type: "tv"} = plan, %PlanUnit{} = unit, prefs) do
    terms(plan, [{unit.season_number, unit.episode_number}], prefs)
  end

  @doc """
  The fit inputs a plan carries, read the one way every caller must
  read them: span sizes from the plan, the threshold from the auto-grab
  settings as a fraction — and no threshold at all when the plan
  captured no span sizes (movies, and a tracking plan whose item has no
  season sizes yet), which turns judging off.
  """
  @spec fit_prefs(Plan.t(), %{pack_min_fit: number()}) :: prefs()
  def fit_prefs(%Plan{} = plan, %{pack_min_fit: percent}) do
    span_sizes = plan.span_sizes || %{}
    %{span_sizes: span_sizes, pack_min_fit: if(span_sizes != %{}, do: percent / 100)}
  end

  defp series_step(_criteria, _kind, false), do: nil

  defp series_step(%Criteria{} = criteria, kind, true),
    do: %{scope: :series, kind: kind, terms: fn _residual -> SearchTerms.series_terms(criteria) end}

  defp season_step(_criteria, _kind, []), do: nil

  defp season_step(%Criteria{} = criteria, kind, seasons) do
    %{
      scope: :season,
      kind: kind,
      terms: fn residual ->
        SearchTerms.season_terms(criteria, residual |> seasons() |> Enum.filter(&(&1 in seasons)))
      end
    }
  end

  defp season_fits?(season, wanted, span_sizes, threshold) do
    wanted_in_season = Enum.count(wanted, &(elem(&1, 0) == season))
    Fit.fits?(wanted_in_season, Fit.span_total({:season, season}, span_sizes), threshold)
  end

  defp seasons(units), do: units |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.sort()
end
