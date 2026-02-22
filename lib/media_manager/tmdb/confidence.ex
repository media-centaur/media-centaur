defmodule MediaManager.TMDB.Confidence do
  @moduledoc """
  Scores TMDB search results against parsed filenames using Jaro string
  distance, with bonuses for matching years and top-result position.
  """

  @doc """
  Score a TMDB search result against a parsed filename.

  `result_title_key` is "title" for movies, "name" for TV.
  `result_year_key` is "release_date" for movies, "first_air_date" for TV.
  `is_top_result?` is true if this is the first result in the list.
  """
  @spec score(String.t(), integer() | nil, map(), String.t(), String.t(), boolean()) :: float()
  def score(parsed_title, parsed_year, result, title_key, year_key, is_top_result?) do
    result_title = result[title_key] || result["name"] || ""
    result_year = extract_year(result[year_key])

    base = String.jaro_distance(normalize(parsed_title), normalize(result_title))
    year_bonus = if parsed_year && result_year && parsed_year == result_year, do: 0.08, else: 0.0
    position_bonus = if is_top_result?, do: 0.05, else: 0.0

    min(base + year_bonus + position_bonus, 1.0)
  end

  @doc "Read the auto-approve threshold from config (default 0.85)."
  def threshold do
    MediaManager.Config.get(:auto_approve_threshold) || 0.85
  end

  defp normalize(str) do
    str
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9 ]/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp extract_year(nil), do: nil
  defp extract_year(""), do: nil

  defp extract_year(date_str) when is_binary(date_str) do
    case Integer.parse(String.slice(date_str, 0, 4)) do
      {year, _} -> year
      :error -> nil
    end
  end
end
