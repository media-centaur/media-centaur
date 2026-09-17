defmodule MediaCentaur.Search.SearchTerms do
  @moduledoc """
  How a search term is spelled — one constructor per scope, the single
  source of truth for every indexer query the app constructs from a
  title. `QueryBuilder` (a pursuit's criteria) and
  `Acquisition.Plans.SearchOrder` (a plan's want) both build their terms
  here, so the two sides of acquisition can never search the same want
  with different strings.

  TV terms come in three scopes: the series title, `Title Season N` +
  `Title SNN` per season, `Title SNNENN` per episode. Movie terms have
  no scope: `Title year`, the year-less `Title` and — when the film has
  a different original-language title — that title are alternate
  phrasings of the same want; the caller searches all of them and picks
  the best of the union. Their order still matters, because an exact tie
  keeps the earlier (year-matched) candidate. Every title is sanitized
  via `TitleForm` (scene names carry no apostrophes or accents).

  Takes the identity half of a `Criteria` — `title`, `tmdb_type`,
  `year`, `original_title`; scope is the caller's argument. Pure — no
  I/O, no DB.
  """

  alias MediaCentaur.Format
  alias MediaCentaur.Search.{Criteria, TitleForm}

  @type search_term :: String.t()

  @doc """
  The Prowlarr/corpus options every term of this title is searched
  with — the category its media type implies, so a title never spends
  the indexer's result page on the books, music and anime that merely
  share a word with it.

  These options are part of the corpus key, so every caller addressing
  the same term must pass **these**. That is why they live beside the
  terms rather than being rebuilt per caller: two callers drifting is
  exactly how one term ends up cached under two keys.
  """
  @spec search_opts(Criteria.t()) :: keyword()
  def search_opts(%Criteria{tmdb_type: :movie}), do: [categories: :movie]
  def search_opts(%Criteria{tmdb_type: :tv}), do: [categories: :tv]

  @doc "The series scope — one term for an all-in-one release."
  @spec series_terms(Criteria.t()) :: [search_term()]
  def series_terms(%Criteria{tmdb_type: :tv} = criteria), do: [title(criteria)]

  @doc """
  The season scope — both text forms per season, the long form first.

  Expects unique, ascending seasons.
  """
  @spec season_terms(Criteria.t(), [pos_integer()]) :: [search_term()]
  def season_terms(%Criteria{tmdb_type: :tv} = criteria, seasons) do
    Enum.flat_map(seasons, fn season ->
      ["#{title(criteria)} Season #{season}", "#{title(criteria)} S#{Format.pad2(season)}"]
    end)
  end

  @doc "The episode scope — one term per `{season, episode}` unit."
  @spec episode_terms(Criteria.t(), [{pos_integer(), pos_integer()}]) :: [search_term()]
  def episode_terms(%Criteria{tmdb_type: :tv} = criteria, units) do
    Enum.map(units, fn {season, episode} ->
      "#{title(criteria)} #{Format.episode_label(season, episode)}"
    end)
  end

  @doc """
  A movie's terms, precise first: `Title year`, then the year-less
  `Title`. Release groups tag a film with whichever year their source
  used (festival premiere vs theatrical), so the year term routinely
  matches a handful of releases while better copies sit only behind the
  year-less one — which is why callers search both rather than stopping
  at the first that hits. No year → one term.
  """
  @spec movie_terms(Criteria.t()) :: [search_term()]
  def movie_terms(%Criteria{tmdb_type: :movie, year: nil} = criteria),
    do: [title(criteria)] ++ original_title_term(criteria)

  def movie_terms(%Criteria{tmdb_type: :movie, year: year} = criteria) when is_integer(year) do
    ["#{title(criteria)} #{year}", title(criteria)] ++ original_title_term(criteria)
  end

  # A foreign film is released under either name, so its original title
  # is one more phrasing of the same want — broadest, hence last. Only
  # when it is genuinely a different title: for the great majority it
  # folds to the canonical one and costs no extra indexer request.
  defp original_title_term(%Criteria{original_title: original} = criteria) when is_binary(original) do
    folded = TitleForm.query(original)

    if TitleForm.compare(folded) == TitleForm.compare(criteria.title), do: [], else: [folded]
  end

  defp original_title_term(%Criteria{}), do: []

  defp title(%Criteria{title: title}), do: TitleForm.query(title)
end
