defmodule MediaCentaur.Search.QueryBuilder do
  @moduledoc """
  Builds an ordered list of Prowlarr search queries from a
  `Search.Criteria` struct.

  Returns `[{query_string, opts}]` ordered best-to-worst — the worker
  tries each in turn until one yields acceptable results. Opts may
  carry `:type` (`:movie` or `:tv`) and `:year` (movies only — episode
  release titles do not embed the show's first-air year, so adding it
  usually shrinks results unhelpfully).

  ## Criteria variants

  - `:tmdb` → TMDB metadata drives query shape (`title [year]` for
    movies, `title SxxEyy` / `title Season N` for TV). One or more
    concrete query strings, no brace expansion.
  - `:prowlarr_query` → the user-typed `manual_query`, expanded via
    `QueryExpander` (brace syntax allowed). No type/year hints
    (Prowlarr's category routing is the user's responsibility). Every
    result is considered a match — the worker routes through the
    decision card for the user to pick.

  Pure function module — no I/O, no DB. Caller projects its
  domain-specific shape (e.g. `Acquisition.Pursuits.Recipe`) into
  `Criteria` via the caller's own `to_criteria/1`.
  """

  alias MediaCentaur.Search.{CourQueries, Criteria, QueryExpander, QueryTerm}
  alias MediaCentaur.Format

  @type opt :: {:type, :movie | :tv} | {:year, integer()}
  @type query :: {String.t(), [opt()]}

  @spec build(Criteria.t()) :: [query()]
  def build(%Criteria{type: :tmdb, tmdb_type: :movie} = criteria),
    do: criteria |> sanitize_title() |> build_movie()

  def build(%Criteria{type: :tmdb, tmdb_type: :tv} = criteria),
    do: criteria |> sanitize_title() |> build_tv()

  def build(%Criteria{type: :prowlarr_query} = criteria), do: build_prowlarr_query(criteria)

  # Constructed queries only — scene names carry no apostrophes, so a
  # verbatim TMDB title can miss every release of the right title.
  # User-typed manual queries pass through untouched.
  defp sanitize_title(criteria), do: %{criteria | title: QueryTerm.sanitize(criteria.title)}

  defp build_movie(%Criteria{title: title, year: nil}), do: [{title, [type: :movie]}]

  # Year query first, year-less fallback second — release names carry
  # whichever year the group's source used (festival premiere vs
  # theatrical), so the year query alone can miss every release of the
  # right movie. The worker tries queries in order.
  defp build_movie(%Criteria{title: title, year: year}) when is_integer(year) do
    [{"#{title} #{year}", [type: :movie, year: year]}, {title, [type: :movie]}]
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
        Enum.uniq(cour ++ [{"#{title} #{season_tag(season)}#{episode_tag(episode)}", [type: :tv]}])

      nil ->
        cour
    end
  end

  defp build_tv(%Criteria{title: title, season_number: season, episode_number: nil})
       when is_integer(season) do
    [
      {"#{title} Season #{season}", [type: :tv]},
      {"#{title} #{season_tag(season)}", [type: :tv]}
    ]
  end

  defp build_tv(%Criteria{title: title, season_number: season, episode_number: episode})
       when is_integer(season) and is_integer(episode) do
    [{"#{title} #{season_tag(season)}#{episode_tag(episode)}", [type: :tv]}]
  end

  # Whole-series fallback (no season/episode known) — rare in the
  # auto-acquisition flow because Refresher always emits a release with
  # episode info, but legitimate when a manual TMDB pursuit targets the
  # series itself.
  defp build_tv(%Criteria{title: title, season_number: nil, episode_number: nil}) do
    [{title, [type: :tv]}]
  end

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
