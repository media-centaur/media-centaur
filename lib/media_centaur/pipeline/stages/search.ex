defmodule MediaCentaur.Pipeline.Stages.Search do
  @moduledoc """
  Pipeline stage 2: searches TMDB for the parsed title/year/type and scores
  results using `TMDB.Confidence`.

  Returns `{:ok, payload}` when confidence >= threshold (auto-approved),
  `{:needs_review, payload}` when confidence is low or no results found,
  or `{:error, reason}` on TMDB API failure.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.DateUtil
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.TMDB.{Client, Confidence}

  @spec run(Payload.t()) :: {:ok, Payload.t()} | {:needs_review, Payload.t()} | {:error, term()}
  def run(%Payload{parsed: parsed} = payload) do
    {search_title, search_year} = search_params(parsed)

    if is_nil(search_title) do
      {:error, :no_title}
    else
      search_type = effective_search_type(parsed)
      Log.info(:pipeline, "searching TMDB for #{inspect(search_title)}, type: #{search_type}")

      case search(search_title, search_year, search_type) do
        {:ok, []} ->
          {:needs_review, %{payload | candidates: []}}

        {:ok, {best, top_matches}} ->
          apply_match(payload, best, top_matches)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp search_params(%{type: :extra, parent_title: parent_title, parent_year: parent_year}) do
    {parent_title, parent_year}
  end

  defp search_params(%{title: title, year: year}) do
    {title, year}
  end

  defp effective_search_type(%{type: :extra, season: season}) when not is_nil(season), do: :tv
  defp effective_search_type(%{type: :extra}), do: :movie
  defp effective_search_type(%{type: :unknown}), do: :unknown
  defp effective_search_type(%{type: type}), do: type

  defp apply_match(payload, {result, score, title_key}, top_matches) do
    tmdb_id = result["id"]
    match_title = result[title_key]
    year_key = if title_key == "title", do: "release_date", else: "first_air_date"
    match_year = DateUtil.extract_year(result[year_key])
    match_poster_path = result["poster_path"]
    tmdb_type = if title_key == "title", do: :movie, else: :tv
    tied? = length(top_matches) > 1
    resolvable_tie? = tied? and resolvable_tie?(payload.parsed, match_year)

    Log.info(:pipeline, fn ->
      threshold = Confidence.threshold()

      status =
        cond do
          tied? and resolvable_tie? -> "approved (tie resolved by year match)"
          tied? -> "needs_review (#{length(top_matches)} tied results)"
          score >= threshold -> "approved"
          true -> "needs_review"
        end

      "#{status}, confidence #{Float.round(score, 2)} " <>
        "(threshold #{threshold}), " <>
        "matched #{inspect(match_title)} (tmdb:#{tmdb_id})"
    end)

    updated =
      %{
        payload
        | tmdb_id: tmdb_id,
          tmdb_type: tmdb_type,
          confidence: score,
          match_title: match_title,
          match_year: match_year,
          match_poster_path: match_poster_path,
          candidates: top_matches
      }

    if score >= Confidence.threshold() and (not tied? or resolvable_tie?) do
      {:ok, updated}
    else
      {:needs_review, updated}
    end
  end

  # A tied movie result can be auto-resolved when the parsed year matches the
  # result year and there are no season/episode indicators (which would suggest
  # the file is actually TV content misclassified as a movie). TMDB sorts by
  # popularity, so the first result is the most likely correct match.
  defp resolvable_tie?(
         %{type: type, year: parsed_year, season: season, episode: episode},
         match_year
       )
       when type in [:movie, :unknown] do
    has_year_match? = not is_nil(parsed_year) and to_string(parsed_year) == to_string(match_year)
    no_episode_indicators? = is_nil(season) and is_nil(episode)
    has_year_match? and no_episode_indicators?
  end

  defp resolvable_tie?(%{type: :tv, year: parsed_year}, match_year) do
    not is_nil(parsed_year) and to_string(parsed_year) == to_string(match_year)
  end

  defp resolvable_tie?(_, _), do: false

  # ---------------------------------------------------------------------------
  # TMDB search
  # ---------------------------------------------------------------------------

  defp search(title, year, :movie) do
    with {:ok, results} <- Client.search_movie(title, year) do
      {:ok, best_match(results, title, year, "title", "release_date")}
    end
  end

  defp search(title, year, :tv) do
    with {:ok, results} <- Client.search_tv(title, year) do
      {:ok, best_match(results, title, year, "name", "first_air_date")}
    end
  end

  defp search(title, year, :unknown) do
    movie_task = Task.async(fn -> Client.search_movie(title, year) end)
    tv_task = Task.async(fn -> Client.search_tv(title, year) end)

    with {:ok, movie_results} <- Task.await(movie_task),
         {:ok, tv_results} <- Task.await(tv_task) do
      movie_match = best_match(movie_results, title, year, "title", "release_date")
      tv_match = best_match(tv_results, title, year, "name", "first_air_date")

      case {movie_match, tv_match} do
        {[], []} ->
          {:ok, []}

        {[], tv} ->
          {:ok, tv}

        {movie, []} ->
          {:ok, movie}

        {{movie_best, _}, {tv_best, _}} ->
          {_, movie_score, _} = movie_best
          {_, tv_score, _} = tv_best

          if movie_score >= tv_score do
            {:ok, movie_match}
          else
            {:ok, tv_match}
          end
      end
    end
  end

  defp best_match([], _parsed_title, _parsed_year, _title_key, _year_key), do: []

  defp best_match(results, parsed_title, parsed_year, title_key, year_key) do
    scored =
      results
      |> Enum.take(5)
      |> Enum.with_index()
      |> Enum.map(fn {result, index} ->
        score =
          Confidence.score(parsed_title, parsed_year, result, title_key, year_key, index == 0)

        {result, score, title_key}
      end)

    {_, best_score, _} = Enum.max_by(scored, fn {_, score, _} -> score end)
    top_matches = Enum.filter(scored, fn {_, score, _} -> score == best_score end)
    {hd(top_matches), top_matches}
  end
end
