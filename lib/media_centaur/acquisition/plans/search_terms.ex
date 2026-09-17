defmodule MediaCentaur.Acquisition.Plans.SearchTerms do
  @moduledoc """
  A plan's search terms, one constructor per scope — single source of
  truth for how a term is spelled, shared by the plan runner, the
  alternatives picker and the corpus keys (all through
  `Plans.SearchOrder`, which decides which scopes to search and in what
  order), so none of them can drift on what "this plan's searches"
  means.

  TV terms come in three scopes: the series title, `Title Season N` +
  `Title SNN` per season, `Title SNNENN` per episode. Movie terms have
  no scope: `Title year`, the
  year-less `Title` and — when the film has a different
  original-language title — that title are alternate phrasings of the
  same want, and the runner searches all of them and picks the best of
  the union. Their order still matters, because an exact tie keeps the
  earlier (year-matched) candidate. Every title is sanitized via
  `Search.TitleForm` (scene names carry no apostrophes).
  """

  alias MediaCentaur.Acquisition.Plans.Plan
  alias MediaCentaur.Format
  alias MediaCentaur.Search.TitleForm

  @type search_term :: String.t()

  @doc """
  The Prowlarr/corpus options every one of this plan's terms is searched
  with — the category its media type implies, so a title never spends
  the indexer's result page on the books, music and anime that merely
  share a word with it.

  These options are part of the corpus key, so the plan runner, the
  alternatives picker and the commit path must all pass **these** when
  addressing a plan's terms. That is why they live here beside the terms
  rather than being rebuilt per caller: the three drifting is exactly how
  one term ends up cached under two keys.
  """
  @spec search_opts(Plan.t()) :: keyword()
  def search_opts(%Plan{tmdb_type: "movie"}), do: [categories: :movie]
  def search_opts(%Plan{tmdb_type: "tv"}), do: [categories: :tv]

  @doc "The series scope — one term for an all-in-one release."
  @spec series_terms(Plan.t()) :: [search_term()]
  def series_terms(%Plan{tmdb_type: "tv"} = plan), do: [title(plan)]

  @doc """
  The season scope — both text forms per season, the long form first.

  Expects unique, ascending seasons (the residual derivation provides this).
  """
  @spec season_terms(Plan.t(), [pos_integer()]) :: [search_term()]
  def season_terms(%Plan{tmdb_type: "tv"} = plan, seasons) do
    Enum.flat_map(seasons, fn season ->
      ["#{title(plan)} Season #{season}", "#{title(plan)} S#{Format.pad2(season)}"]
    end)
  end

  @doc "The episode scope — one term per `{season, episode}` unit."
  @spec episode_terms(Plan.t(), [{pos_integer(), pos_integer()}]) :: [search_term()]
  def episode_terms(%Plan{tmdb_type: "tv"} = plan, units) do
    Enum.map(units, fn {season, episode} ->
      "#{title(plan)} #{Format.episode_label(season, episode)}"
    end)
  end

  @doc """
  A movie's terms, precise first: `Title year`, then the year-less
  `Title`. Release groups tag a film with whichever year their source
  used (festival premiere vs theatrical), so the year term routinely
  matches a handful of releases while better copies sit only behind the
  year-less one — which is why the runner searches both rather than
  stopping at the first that hits. No year → one term.
  """
  @spec movie_terms(Plan.t()) :: [search_term()]
  def movie_terms(%Plan{tmdb_type: "movie", year: nil} = plan),
    do: [title(plan)] ++ original_title_term(plan)

  def movie_terms(%Plan{tmdb_type: "movie"} = plan) do
    ["#{title(plan)} #{plan.year}", title(plan)] ++ original_title_term(plan)
  end

  # A foreign film is released under either name, so its original title
  # is one more phrasing of the same want — broadest, hence last. Only
  # when it is genuinely a different title: for the great majority it
  # folds to the canonical one and costs no extra indexer request.
  defp original_title_term(%Plan{original_title: original} = plan) when is_binary(original) do
    folded = TitleForm.query(original)

    if TitleForm.compare(folded) == TitleForm.compare(plan.title), do: [], else: [folded]
  end

  defp original_title_term(%Plan{}), do: []

  defp title(plan), do: TitleForm.query(plan.title)
end
