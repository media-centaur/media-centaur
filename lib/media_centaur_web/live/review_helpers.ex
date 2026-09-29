defmodule MediaCentaurWeb.ReviewHelpers do
  @moduledoc """
  Pure helper functions for the review LiveView — reason classification,
  candidate analysis, confidence display, and sorting.
  """

  # --- Reason Classification ---

  # An approved file waits for the library to link it (`:importing`); a
  # file the library did not link comes back with the reason (`:not_added`).
  def review_reason(%{status: :approved}), do: :importing
  def review_reason(%{error_message: message}) when is_binary(message), do: :not_added

  def review_reason(file) do
    cond do
      is_nil(file.tmdb_id) -> :no_results
      tied_candidates?(file) -> :tied
      true -> :low_confidence
    end
  end

  def count_by_reason(groups) do
    zero = %{no_results: 0, tied: 0, low_confidence: 0, importing: 0, not_added: 0}

    Enum.reduce(groups, zero, fn group, acc ->
      reason = review_reason(group.representative)
      Map.update!(acc, reason, &(&1 + 1))
    end)
  end

  # --- Reason Display ---

  def reason_label(:no_results), do: "No TMDB results"
  def reason_label(:low_confidence), do: "Low confidence"
  def reason_label(:tied), do: "Tied match"
  def reason_label(:importing), do: "Importing"
  def reason_label(:not_added), do: "Not added"

  def reason_text_class(:no_results), do: "text-error"
  def reason_text_class(:low_confidence), do: "text-warning"
  def reason_text_class(:tied), do: "text-info"
  def reason_text_class(:importing), do: "text-base-content/60"
  def reason_text_class(:not_added), do: "text-error"

  # --- Candidate Analysis ---

  def tied_candidates?(%{candidates: candidates}) when is_list(candidates) do
    case candidates do
      [first | [_ | _] = rest] ->
        first_score = first["score"]
        Enum.all?(rest, fn candidate -> candidate["score"] == first_score end)

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

  # Groups awaiting a decision first, weakest match first; importing groups
  # need nothing from the reviewer and sort last.
  def sort_groups(groups) do
    Enum.sort_by(groups, fn %{representative: file} ->
      {if(review_reason(file) == :importing, do: 1, else: 0), if(file.tmdb_id, do: 1, else: 0),
       file.confidence || 0}
    end)
  end
end
