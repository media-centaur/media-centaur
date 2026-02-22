defmodule MediaManager.Library.WatchedFile.Changes.SearchTmdb do
  @moduledoc """
  Ash change that searches TMDB for the parsed title/year/type and scores
  results using `TMDB.Confidence`. Sets the file to `:approved` or
  `:pending_review` based on the confidence threshold.
  """
  use Ash.Resource.Change
  alias MediaManager.TMDB.{Client, Confidence}

  def change(changeset, _opts, _context) do
    parsed_title =
      Ash.Changeset.get_attribute(changeset, :search_title) ||
        Ash.Changeset.get_attribute(changeset, :parsed_title)

    parsed_year = Ash.Changeset.get_attribute(changeset, :parsed_year)
    parsed_type = Ash.Changeset.get_attribute(changeset, :parsed_type) || :unknown

    if is_nil(parsed_title) do
      changeset
      |> Ash.Changeset.change_attribute(:state, :error)
      |> Ash.Changeset.change_attribute(:error_message, "no parsed title available for search")
    else
      search_and_apply(changeset, parsed_title, parsed_year, parsed_type)
    end
  end

  defp search_and_apply(changeset, parsed_title, parsed_year, parsed_type) do
    search_type = effective_search_type(changeset, parsed_type)

    case search(parsed_title, parsed_year, search_type) do
      {:ok, []} ->
        Ash.Changeset.change_attribute(changeset, :state, :pending_review)

      {:ok, {result, score, title_key}} ->
        tmdb_id = to_string(result["id"])
        match_title = result[title_key]
        year_key = if title_key == "title", do: "release_date", else: "first_air_date"
        match_year = extract_year(result[year_key])
        match_poster_path = result["poster_path"]
        next_state = if score >= Confidence.threshold(), do: :approved, else: :pending_review

        changeset
        |> Ash.Changeset.change_attribute(:tmdb_id, tmdb_id)
        |> Ash.Changeset.change_attribute(:confidence_score, score)
        |> Ash.Changeset.change_attribute(:match_title, match_title)
        |> Ash.Changeset.change_attribute(:match_year, match_year)
        |> Ash.Changeset.change_attribute(:match_poster_path, match_poster_path)
        |> Ash.Changeset.change_attribute(:state, next_state)

      {:error, reason} ->
        changeset
        |> Ash.Changeset.change_attribute(:state, :error)
        |> Ash.Changeset.change_attribute(:error_message, inspect(reason))
    end
  end

  defp effective_search_type(changeset, :extra) do
    if Ash.Changeset.get_attribute(changeset, :season_number), do: :tv, else: :movie
  end

  defp effective_search_type(_changeset, type), do: type

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

        {[], match} ->
          {:ok, match}

        {match, []} ->
          {:ok, match}

        {{_, movie_score, _} = movie, {_, tv_score, _}} when movie_score >= tv_score ->
          {:ok, movie}

        {_movie, tv} ->
          {:ok, tv}
      end
    end
  end

  defp best_match([], _parsed_title, _parsed_year, _title_key, _year_key), do: []

  defp best_match(results, parsed_title, parsed_year, title_key, year_key) do
    results
    |> Enum.take(5)
    |> Enum.with_index()
    |> Enum.map(fn {result, index} ->
      score = Confidence.score(parsed_title, parsed_year, result, title_key, year_key, index == 0)
      {result, score, title_key}
    end)
    |> Enum.max_by(fn {_, score, _} -> score end)
  end

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil
  defp extract_year(<<year::binary-size(4), _rest::binary>>), do: year
end
