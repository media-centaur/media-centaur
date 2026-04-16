defmodule MediaCentarrWeb.ReviewHelpers do
  @moduledoc """
  Pure helper functions for the review LiveView — reason classification,
  candidate analysis, confidence display, and sorting.
  """

  # --- Reason Classification ---

  def review_reason(file) do
    cond do
      is_nil(file.tmdb_id) -> :no_results
      tied_candidates?(file) -> :tied
      true -> :low_confidence
    end
  end

  def count_by_reason(groups) do
    Enum.reduce(groups, %{no_results: 0, tied: 0, low_confidence: 0}, fn group, acc ->
      reason = review_reason(group.representative)
      Map.update!(acc, reason, &(&1 + 1))
    end)
  end

  # --- Reason Display ---

  def reason_label(:no_results), do: "No TMDB results"
  def reason_label(:low_confidence), do: "Low confidence"
  def reason_label(:tied), do: "Tied match"

  def reason_text_class(:no_results), do: "text-error"
  def reason_text_class(:low_confidence), do: "text-warning"
  def reason_text_class(:tied), do: "text-info"

  # --- Candidate Analysis ---

  def tied_candidates?(%{candidates: candidates}) when is_list(candidates) do
    case candidates do
      [_, _ | _] ->
        scores = Enum.map(candidates, & &1["score"])
        length(Enum.uniq(scores)) == 1

      _ ->
        false
    end
  end

  def tied_candidates?(_), do: false

  def sort_candidates_by_year(candidates) do
    Enum.sort_by(candidates, fn candidate ->
      case candidate["year"] do
        nil -> 9999
        year when is_binary(year) -> String.to_integer(year)
        year when is_integer(year) -> year
      end
    end)
  end

  # --- Confidence Display ---

  def confidence_text_class(score) when score >= 0.8, do: "text-success"
  def confidence_text_class(score) when score >= 0.5, do: "text-warning"
  def confidence_text_class(_), do: "text-error"

  def confidence_bar_class(score) when score >= 0.8, do: "bg-success"
  def confidence_bar_class(score) when score >= 0.5, do: "bg-warning"
  def confidence_bar_class(_), do: "bg-error"

  # --- Type Formatting ---

  def format_type("movie"), do: "Movie"
  def format_type("tv"), do: "TV"
  def format_type("extra"), do: "Extra"
  def format_type("unknown"), do: "Unknown"
  def format_type(nil), do: "Unknown"
  def format_type(type) when is_atom(type), do: type |> Atom.to_string() |> String.capitalize()
  def format_type(type), do: type |> to_string() |> String.capitalize()

  # --- Sort ---

  def sort_groups(groups) do
    Enum.sort_by(groups, fn %{representative: file} ->
      {if(file.tmdb_id, do: 1, else: 0), file.confidence || 0}
    end)
  end
end
