defmodule MediaCentaur.Pipeline.Stages.Search do
  @moduledoc """
  Pipeline stage 2: identifies the parsed title. A name a person answered
  in Review before (`Review.remembered_match/3`) takes that answer;
  otherwise TMDB is searched for the parsed title/year/type and the
  results are scored using `TMDB.Confidence`. When the search cannot
  decide and the file came from a grab of ours, the grab's identity
  answers (`answer_from_grab/2`).

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
        nil ->
          payload |> search_tmdb(search_title, search_year, search_type) |> answer_from_grab(payload)

        remembered ->
          apply_remembered(payload, remembered)
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

  # The search could not decide — nothing found under the release's name, a
  # tie, a guess below the threshold — but acquisition knows what it asked
  # for (`Acquisition.GrabProvenance`). The grab's identity answers when the
  # search found nothing, or found the grab's title among what it found; a
  # search that found a different title instead is a conflict for a person.
  defp answer_from_grab({:needs_review, searched} = outcome, %Payload{file_path: file_path} = payload)
       when is_binary(file_path) do
    with %TitleIdentity{} = wanted <- Acquisition.GrabProvenance.wanted_identity_for_file(file_path),
         true <- grab_among_found?(wanted, searched) do
      Log.info(
        :pipeline,
        "search undecided — took the grab's identity tmdb:#{wanted.tmdb_id} (#{wanted.title})"
      )

      {:ok,
       %{
         payload
         | tmdb_id: String.to_integer(wanted.tmdb_id),
           tmdb_type: wanted.tmdb_type,
           confidence: 1.0,
           match_title: wanted.title,
           match_year: wanted.year && to_string(wanted.year),
           match_poster_path: nil,
           candidates: []
       }}
    else
      _no_grab_or_conflict -> outcome
    end
  end

  defp answer_from_grab(outcome, _payload), do: outcome

  defp grab_among_found?(_wanted, %Payload{tmdb_id: nil}), do: true

  defp grab_among_found?(
         %TitleIdentity{tmdb_id: wanted_id, tmdb_type: type},
         %Payload{tmdb_type: type} = searched
       ) do
    found = for {result, _score, _title_key} <- searched.candidates || [], do: to_string(result["id"])
    wanted_id in [to_string(searched.tmdb_id) | found]
  end

  defp grab_among_found?(_wanted, _searched), do: false

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

    case grab_conflict(payload, updated) do
      nil -> {:ok, updated}
      wanted_title -> {:needs_review, %{updated | wanted_title: wanted_title}}
    end
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

    wanted_title = grab_conflict(payload, updated)

    cond do
      wanted_title -> {:needs_review, %{updated | wanted_title: wanted_title}}
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
  # Returns the title the grab wanted when the match contradicts it, which
  # the review row names as its reason; nil when nothing is contradicted.
  defp grab_conflict(%Payload{file_path: file_path}, matched) when is_binary(file_path) do
    wanted = Acquisition.GrabProvenance.wanted_identity_for_file(file_path)
    if contradicts_match?(wanted, matched), do: wanted.title
  end

  defp grab_conflict(_payload, _matched), do: nil

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

  # Both searches at once, unlinked: a crash or a timeout in one is this
  # file's search failing, never the processor's. The budget covers two
  # requests that may each wait on `TMDB.RateLimiter` first.
  @unknown_type_search_timeout_ms 60_000

  defp search(title, year, :unknown) do
    [movie, tv] =
      [
        fn -> with_year_fallback(&Client.search_movie/2, title, year) end,
        fn -> with_year_fallback(&Client.search_tv/2, title, year) end
      ]
      |> Enum.map(&Task.Supervisor.async_nolink(MediaCentaur.TaskSupervisor, &1))
      |> Task.yield_many(timeout: @unknown_type_search_timeout_ms)
      |> Enum.map(&search_outcome/1)

    with {:ok, movie_results} <- movie,
         {:ok, tv_results} <- tv do
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
  # One `Task.yield_many/2` entry → the search's `{:ok, results} | {:error, reason}`.
  defp search_outcome({_task, {:ok, outcome}}), do: outcome
  defp search_outcome({_task, {:exit, reason}}), do: {:error, {:search_crashed, reason}}
  defp search_outcome({task, nil}), do: task |> Task.shutdown(:brutal_kill) |> late_search_outcome()

  defp late_search_outcome({:ok, outcome}), do: outcome
  defp late_search_outcome({:exit, reason}), do: {:error, {:search_crashed, reason}}
  defp late_search_outcome(nil), do: {:error, :search_timeout}

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
