defmodule MediaCentaur.Search.QueryBuilder do
  @moduledoc """
  Builds an ordered list of Prowlarr search queries from a
  `Search.Criteria` struct.

  Returns `[{query_string, opts}]`. Opts carry `:categories`
  (`:movie` or `:tv`) for TMDB criteria and nothing for a user-typed
  query. The order is precise-to-broad, but it is the *caller* that
  decides what to do with it: a movie's queries are alternate phrasings
  of one want and every one is searched, while TV's are a narrowing
  ladder walked only as far as coverage requires.

  ## Criteria variants

  - `:tmdb` → TMDB metadata drives query shape (`title [year]` for
    movies, `title SxxEyy` / `title Season N` for TV). One or more
    concrete query strings, no brace expansion.
  - `:prowlarr_query` → the user-typed `manual_query`, expanded via
    `QueryExpander` (brace syntax allowed). No category hint —
    Prowlarr's routing is the user's responsibility. Every result is
    considered a match, and the worker routes through the decision card
    for the user to pick.

  Pure function module — no I/O, no DB. Caller projects its
  domain-specific shape (e.g. `Acquisition.Pursuits.Recipe`) into
  `Criteria` via the caller's own `to_criteria/1`.
  """

  alias MediaCentaur.Search.{CourQueries, Criteria, QueryExpander, QueryTerm}
  alias MediaCentaur.Format

  @type opt :: {:categories, :movie | :tv}
  @type query :: {String.t(), [opt()]}

  @spec build(Criteria.t()) :: [query()]
  def build(%Criteria{type: :tmdb, tmdb_type: :movie} = criteria),
    do: criteria |> sanitize_title() |> build_movie() |> with_categories(:movie)

  def build(%Criteria{type: :tmdb, tmdb_type: :tv} = criteria),
    do: criteria |> sanitize_title() |> build_tv() |> with_categories(:tv)

  def build(%Criteria{type: :prowlarr_query} = criteria), do: build_prowlarr_query(criteria)

  # Constructed queries only — scene names carry no apostrophes, so a
  # verbatim TMDB title can miss every release of the right title.
  # User-typed manual queries pass through untouched.
  defp sanitize_title(criteria), do: %{criteria | title: QueryTerm.sanitize(criteria.title)}

  defp build_movie(%Criteria{title: title, year: nil}), do: [{title, []}]

  # Year query first, year-less fallback second — release names carry
  # whichever year the group's source used (festival premiere vs
  # theatrical), so the year query alone can miss every release of the
  # right movie. The worker tries queries in order.
  defp build_movie(%Criteria{title: title, year: year}) when is_integer(year) do
    [{"#{title} #{year}", []}, {title, []}]
  end

  # Later-cour residual: the first-run `Season N` query is wrong (it
  # surfaces the first-run pack the coverage guard refused), so emit the
  # run-shaped queries instead. A residual episode keeps its precise
  # `SxxExx` query as a fallback alongside the cour queries.
  defp build_tv(%Criteria{run: %{index: index} = run, title: title} = criteria)
       when is_integer(index) and index > 0 do
    cour = CourQueries.build(title, run)

    case criteria.episode_number do
      episode when is_integer(episode) ->
        season = criteria.season_number
        Enum.uniq(cour ++ [{"#{title} #{season_tag(season)}#{episode_tag(episode)}", []}])

      nil ->
        cour
    end
  end

  defp build_tv(%Criteria{title: title, season_number: season, episode_number: nil})
       when is_integer(season) do
    [
      {"#{title} Season #{season}", []},
      {"#{title} #{season_tag(season)}", []}
    ]
  end

  defp build_tv(%Criteria{title: title, season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    [{"#{title} #{season_tag(season)}#{episode_tag(episode)}", []}]
  end

  # Whole-series fallback (no season/episode known) — rare in the
  # auto-acquisition flow because Refresher always emits a release with
  # episode info, but legitimate when a manual TMDB pursuit targets the
  # series itself.
  defp build_tv(%Criteria{title: title, season_number: nil, episode_number: nil}) do
    [{title, []}]
  end

  # Every TMDB-derived query is scoped to the category its type implies,
  # so an unfiltered title never spends the indexer's result page on the
  # books, music and anime that merely share a word with it. A user-typed
  # query gets none — routing a manual search is the user's business.
  defp with_categories(queries, kind),
    do: Enum.map(queries, fn {query, opts} -> {query, Keyword.put(opts, :categories, kind)} end)

  defp build_prowlarr_query(%Criteria{manual_query: nil}), do: []

  defp build_prowlarr_query(%Criteria{manual_query: query}) when is_binary(query) do
    case QueryExpander.expand(query) do
      {:ok, parts} -> Enum.map(parts, &{&1, []})
      {:error, _} -> [{query, []}]
    end
  end

  defp season_tag(season), do: "S" <> Format.pad2(season)
  defp episode_tag(episode), do: "E" <> Format.pad2(episode)
end
