defmodule MediaCentaur.Search.QueryBuilder do
  @moduledoc """
  Builds an ordered list of Prowlarr search queries from a
  `Search.Criteria` struct.

  Returns `[{query_string, opts}]`. Opts carry `:categories`
  (`:movie` or `:tv`) for TMDB criteria and nothing for a user-typed
  query. The strings themselves come from `SearchTerms`, the one place
  a term is spelled, so a pursuit and a plan search the same want with
  the same query. The order is precise-to-broad, but it is the *caller*
  that decides what to do with it: a movie's queries are alternate
  phrasings of one want and every one is searched, while a TV unit is
  either covered by a query's results or not.

  ## Criteria variants

  - `:tmdb` → TMDB metadata drives query shape (`title [year]` for
    movies, `title SxxEyy` / `title Season N` for TV). One or more
    concrete query strings, no brace expansion.
  - `:prowlarr_query` → the user-typed `manual_query`, expanded via
    `QueryExpander` (brace syntax allowed). No category hint —
    Prowlarr's routing is the user's responsibility. Every result is
    considered a match, and the worker routes through the decision card
    for the user to pick.

  `build/1` is what a search *for* the criteria runs. `fallback/1` is
  what a search runs when that found nothing and the caller is willing
  to be offered a pack: for a TV episode, its season's terms then the
  series term, narrowest first. Pure function module — no I/O, no DB.
  Caller projects its domain-specific shape (e.g.
  `Acquisition.Pursuits.Recipe`) into `Criteria` via the caller's own
  `to_criteria/1`.
  """

  alias MediaCentaur.Search.{CourQueries, Criteria, QueryExpander, SearchTerms, TitleForm}

  @type opt :: {:categories, :movie | :tv}
  @type query :: {String.t(), [opt()]}

  @spec build(Criteria.t()) :: [query()]
  def build(%Criteria{type: :tmdb, tmdb_type: :movie} = criteria),
    do: criteria |> SearchTerms.movie_terms() |> with_categories(criteria)

  def build(%Criteria{type: :tmdb, tmdb_type: :tv} = criteria),
    do: criteria |> build_tv() |> with_categories(criteria)

  def build(%Criteria{type: :prowlarr_query} = criteria), do: build_prowlarr_query(criteria)

  @doc """
  The wider queries that can only offer a pack for a TV episode: its
  season's two terms, then the series term — narrowest first, so the
  least over-broad pack surfaces first. Empty for every other criteria:
  a movie's phrasings are all in `build/1`, a season or series criteria
  is already the widest thing it could want, and a user-typed query has
  no scope to widen.
  """
  @spec fallback(Criteria.t()) :: [query()]
  def fallback(
        %Criteria{type: :tmdb, tmdb_type: :tv, season_number: season, episode_number: episode} = criteria
      )
      when is_integer(season) and is_integer(episode) do
    with_categories(
      SearchTerms.season_terms(criteria, [season]) ++ SearchTerms.series_terms(criteria),
      criteria
    )
  end

  def fallback(%Criteria{}), do: []

  # Later-cour residual: the first-run `Season N` query is wrong (it
  # surfaces the first-run pack the coverage guard refused), so emit the
  # run-shaped queries instead. A residual episode keeps its precise
  # `SxxExx` query as a fallback alongside the cour queries.
  defp build_tv(%Criteria{run: %{index: index} = run} = criteria) when is_integer(index) and index > 0 do
    cour = criteria.title |> TitleForm.query() |> CourQueries.build(run) |> Enum.map(&elem(&1, 0))

    case criteria.episode_number do
      episode when is_integer(episode) ->
        Enum.uniq(cour ++ SearchTerms.episode_terms(criteria, [{criteria.season_number, episode}]))

      nil ->
        cour
    end
  end

  defp build_tv(%Criteria{season_number: season, episode_number: nil} = criteria)
       when is_integer(season), do: SearchTerms.season_terms(criteria, [season])

  defp build_tv(%Criteria{season_number: season, episode_number: episode} = criteria)
       when is_integer(season) and is_integer(episode),
       do: SearchTerms.episode_terms(criteria, [{season, episode}])

  # Whole-series query (no season/episode known) — rare in the
  # auto-acquisition flow because Refresher always emits a release with
  # episode info, but legitimate when a manual TMDB pursuit targets the
  # series itself.
  defp build_tv(%Criteria{season_number: nil, episode_number: nil} = criteria),
    do: SearchTerms.series_terms(criteria)

  # Every TMDB-derived query is scoped to the category its type implies,
  # so an unfiltered title never spends the indexer's result page on the
  # books, music and anime that merely share a word with it. A user-typed
  # query gets none — routing a manual search is the user's business.
  defp with_categories(terms, %Criteria{} = criteria) do
    opts = SearchTerms.search_opts(criteria)
    Enum.map(terms, &{&1, opts})
  end

  defp build_prowlarr_query(%Criteria{manual_query: nil}), do: []

  defp build_prowlarr_query(%Criteria{manual_query: query}) when is_binary(query) do
    case QueryExpander.expand(query) do
      {:ok, parts} -> Enum.map(parts, &{&1, []})
      {:error, _} -> [{query, []}]
    end
  end
end
