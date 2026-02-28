defmodule MediaCentaur.Review.Intake do
  @moduledoc """
  Creates `PendingFile` records from pipeline data.

  This is the Review context's inbound API. When the pipeline's Search stage
  returns `{:needs_review, payload}`, this module maps the payload fields into
  a PendingFile record for human review.
  """

  alias MediaCentaur.DateUtil
  alias MediaCentaur.Pipeline.Payload
  alias MediaCentaur.Review.PendingFile

  @spec create_from_payload(Payload.t()) :: {:ok, PendingFile.t()} | {:error, term()}
  def create_from_payload(%Payload{} = payload) do
    attrs = build_attrs(payload)

    PendingFile
    |> Ash.Changeset.for_create(:find_or_create, attrs)
    |> Ash.create()
  end

  defp build_attrs(payload) do
    {search_title, search_year} = search_params(payload.parsed)

    %{
      file_path: payload.file_path,
      watch_directory: payload.watch_directory,
      parsed_title: search_title,
      parsed_year: search_year,
      parsed_type: type_to_string(payload.parsed.type),
      season_number: payload.parsed.season,
      episode_number: payload.parsed.episode,
      tmdb_id: payload.tmdb_id,
      tmdb_type: type_to_string(payload.tmdb_type),
      confidence: payload.confidence,
      match_title: payload.match_title,
      match_year: payload.match_year,
      match_poster_path: payload.match_poster_path,
      candidates: normalize_candidates(payload.candidates)
    }
  end

  defp search_params(%{type: :extra, parent_title: title, parent_year: year}), do: {title, year}
  defp search_params(%{title: title, year: year}), do: {title, year}

  defp type_to_string(nil), do: nil
  defp type_to_string(type) when is_atom(type), do: Atom.to_string(type)
  defp type_to_string(type) when is_binary(type), do: type

  defp normalize_candidates(nil), do: []
  defp normalize_candidates([]), do: []

  defp normalize_candidates(candidates) do
    Enum.map(candidates, &normalize_candidate/1)
  end

  defp normalize_candidate({raw_result, score, title_key}) do
    year_key = if title_key == "title", do: "release_date", else: "first_air_date"

    %{
      "tmdb_id" => raw_result["id"],
      "title" => raw_result[title_key],
      "year" => DateUtil.extract_year(raw_result[year_key]),
      "score" => score,
      "poster_path" => raw_result["poster_path"]
    }
  end
end
