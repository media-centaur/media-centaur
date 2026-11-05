defmodule MediaCentaur.Pipeline.Stages.Search do
  @moduledoc """
  Pipeline stage 2: identifies the parsed title. A name a person answered
  in Review before (`Review.remembered_match/3`) takes that answer;
  otherwise TMDB is searched for the parsed title/year/type and the
  results are scored using `TMDB.Confidence`.

  Returns `{:ok, payload}` when confidence >= threshold (auto-approved),
  `{:needs_review, payload}` when confidence is low or no results found,
  or `{:error, reason}` on TMDB API failure.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.DateUtil
  alias MediaCentaur.Parser
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Acquisition
  alias MediaCentaur.Review
  alias MediaCentaur.TMDB.{Client, Confidence, TitleIdentity}

  @behaviour MediaCentaur.Pipeline.Stage

  @spec run(Payload.t()) :: {:ok, Payload.t()} | {:needs_review, Payload.t()} | {:error, term()}
  @impl true
  def run(%Payload{parsed: parsed} = payload) do
    {search_title, search_year} = Parser.search_params(parsed)

    if is_nil(search_title) do
      {:error, :no_title}
    else
      search_type = Parser.effective_media_type(parsed)

      case Review.remembered_match(search_title, search_type, search_year) do
        nil -> search_tmdb(payload, search_title, search_year, search_type)
        remembered -> apply_remembered(payload, remembered)
      end
    end
  end

  defp search_tmdb(payload, search_title, search_year, search_type) do
    Log.info(:pipeline, "searching TMDB — #{search_title} (#{search_type})")

    case search(search_title, search_year, search_type) do
      {:ok, []} ->
        {:needs_review, %{payload | candidates: []}}

      {:ok, {best, top_matches}} ->
        apply_match(payload, best, top_matches)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A person answered this name in Review before (`Review.RememberedMatch`):
  # their answer stands in for the search. It is still checked against the
  # grab that fetched the file, like any match.
  defp apply_remembered(payload, remembered) do
    Log.info(
      :pipeline,
      "remembered match for #{inspect(remembered.parsed_title)} — tmdb:#{remembered.tmdb_id}"
    )

    updated = %{
      payload
      | tmdb_id: remembered.tmdb_id,
        tmdb_type: String.to_existing_atom(remembered.tmdb_type),
        confidence: 1.0,
        match_title: remembered.match_title,
        match_year: remembered.match_year,
        match_poster_path: remembered.match_poster_path,
        candidates: []
    }

    if contradicts_grab?(payload, updated), do: {:needs_review, updated}, else: {:ok, updated}
  end

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

      "matched #{Float.round(score, 2)} for tmdb:#{tmdb_id} — #{status}, " <>
        "threshold #{threshold}, #{inspect(match_title)}"
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

    cond do
      contradicts_grab?(payload, updated) -> {:needs_review, updated}
      score < Confidence.threshold() -> {:needs_review, updated}
      tied? and not resolvable_tie? -> {:needs_review, updated}
      true -> {:ok, updated}
    end
  end

  # Confidence measures how well a *name* matched. It cannot see that
  # acquisition asked for a different film — two works genuinely share a
  # name, and the folded comparison that makes `Noémie` match `Noemie`
  # makes them indistinguishable. So when the grab that brought this file
  # here named an identity, and the match contradicts it by external id,
  # a person decides. Silence here is what turned one bad grab into a
  # loop: the want could never close, so the sweep re-grabbed daily.
  defp contradicts_grab?(%Payload{file_path: file_path}, matched) when is_binary(file_path) do
    file_path
    |> Acquisition.GrabProvenance.wanted_identity_for_file()
    |> contradicts_match?(matched)
  end

  defp contradicts_grab?(_payload, _matched), do: false

  # A TMDB id only names a work within its own type — movie 550 and
  # series 550 are unrelated. Comparing across types would read a
  # coincidence as agreement and a difference as a fault, so a
  # type-crossing match is left to confidence, as before.
  defp contradicts_match?(%TitleIdentity{tmdb_type: type} = wanted, %Payload{tmdb_type: type} = matched) do
    verdict = TitleIdentity.compare(wanted, %{tmdb_id: matched.tmdb_id})

    if verdict == :mismatch do
      Log.warning(
        :pipeline,
        "grab wanted #{wanted.tmdb_type}:#{wanted.tmdb_id} (#{wanted.title}) but this file " <>
          "matches tmdb:#{matched.tmdb_id} (#{matched.match_title}) — sending to review"
      )
    end

    verdict == :mismatch
  end

  defp contradicts_match?(_wanted, _matched), do: false

  # Tied results can be resolved when the parsed year matches the top
  # match's year. TMDB sorts by popularity within the same title/year,
  # so the first matching result is the most likely correct one.
  defp resolvable_tie?(%{year: parsed_year}, match_year) when not is_nil(parsed_year) do
    to_string(parsed_year) == to_string(match_year)
  end

  defp resolvable_tie?(_, _), do: false

  # ---------------------------------------------------------------------------
  # TMDB search
  # ---------------------------------------------------------------------------

  defp search(title, year, :movie) do
    with {:ok, results} <- with_year_fallback(&Client.search_movie/2, title, year) do
      {:ok, best_match(results, title, year, "title", "release_date")}
    end
  end

  defp search(title, year, :tv) do
    with {:ok, results} <- with_year_fallback(&Client.search_tv/2, title, year) do
      {:ok, best_match(results, title, year, "name", "first_air_date")}
    end
  end

  defp search(title, year, :unknown) do
    movie_task =
      Task.Supervisor.async(MediaCentaur.TaskSupervisor, fn ->
        with_year_fallback(&Client.search_movie/2, title, year)
      end)

    tv_task =
      Task.Supervisor.async(MediaCentaur.TaskSupervisor, fn ->
        with_year_fallback(&Client.search_tv/2, title, year)
      end)

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

  # The year param is a hard TMDB filter — a wrongly-parsed year (or an
  # off-by-one release year: festival premiere vs theatrical) would turn
  # a findable title into a silent miss. Zero year-filtered results
  # retry year-less; `Confidence.score/6` still penalizes the mismatch,
  # so a dubious year lands in review rather than vanishing.
  defp with_year_fallback(search_fun, title, year) do
    case search_fun.(title, year) do
      {:ok, []} when not is_nil(year) -> search_fun.(title, nil)
      result -> result
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
