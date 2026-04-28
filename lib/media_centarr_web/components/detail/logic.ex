defmodule MediaCentarrWeb.Components.Detail.Logic do
  @moduledoc """
  Pure helpers for the entity detail panel — stat-grid composition, score
  visibility, and the small string transforms used in the metadata row.

  Per ADR-030, all non-trivial branching that would otherwise live in the
  detail panel templates is hoisted here so it can be unit-tested with
  `async: true` and `build_*` factory helpers.
  """

  @doc """
  Returns the "At a glance" stat grid for an entity.

  Cells whose value is `nil` or blank are omitted; if no cells have data the
  result is an empty list and the calling template can hide the section.

  Variants:

    * `stat_grid_for(:movie, movie)` — Director / Original language / Country / Studio
    * `stat_grid_for(:tv_series, tv_series)` — Network / Original language / Country / Status
    * `stat_grid_for(:movie_series, movie_series, movies)` — Movies / First released / Latest
  """
  def stat_grid_for(:movie, movie) do
    reject_blank_values([
      {"Director", movie.director},
      {"Original language", movie.original_language},
      {"Country", movie.country_code},
      {"Studio", movie.studio}
    ])
  end

  def stat_grid_for(:tv_series, tv_series) do
    reject_blank_values([
      {"Network", tv_series.network},
      {"Original language", tv_series.original_language},
      {"Country", tv_series.country_code},
      {"Status", humanize_status(tv_series.status)}
    ])
  end

  def stat_grid_for(:movie_series, _movie_series, movies) when is_list(movies) do
    case length(movies) do
      0 ->
        []

      count ->
        years =
          movies
          |> Enum.map(&year_from_date(&1.date_published))
          |> Enum.reject(&is_nil/1)
          |> Enum.sort()

        reject_blank_values([
          {"Movies", Integer.to_string(count)},
          {"First released", List.first(years)},
          {"Latest", List.last(years)}
        ])
    end
  end

  @doc """
  True when an entity's TMDB rating should be displayed.

  We hide the score card for entities with no votes — TMDB returns `0.0`
  for unrated titles, which would otherwise render as a dishonest "0/10".
  """
  def score_visible?(%{aggregate_rating_value: rating}) when is_number(rating) and rating > 0, do: true

  def score_visible?(_), do: false

  @doc """
  Extracts the 4-digit year from an ISO 8601 date string. Returns `nil` for
  any input that doesn't match.
  """
  def year_from_date(nil), do: nil
  def year_from_date(""), do: nil

  def year_from_date(<<year::binary-size(4), "-", _rest::binary>>) when byte_size(year) == 4 do
    if String.match?(year, ~r/^\d{4}$/), do: year
  end

  def year_from_date(_), do: nil

  @doc """
  Formats an ISO 8601 duration string (`"PT1H55M"`) into a compact human
  form (`"1h 55m"`). Returns `nil` for `nil`, blank, or malformed input —
  never crashes on bad data.
  """
  def format_duration(nil), do: nil
  def format_duration(""), do: nil

  def format_duration("PT" <> rest) do
    {hours, after_hours} = take_iso_component(rest, "H")
    {minutes, _tail} = take_iso_component(after_hours, "M")

    case {hours, minutes} do
      {nil, nil} -> nil
      {nil, m} -> "#{m}m"
      {h, nil} -> "#{h}h"
      {h, m} -> "#{h}h #{m}m"
    end
  end

  def format_duration(_), do: nil

  defp take_iso_component(string, suffix) do
    case String.split(string, suffix, parts: 2) do
      [num, rest] ->
        case Integer.parse(num) do
          {n, ""} -> {n, rest}
          _ -> {nil, string}
        end

      [_only] ->
        {nil, string}
    end
  end

  @doc """
  Renders an entity's status atom as a display string. Returns `nil` for
  `nil`, passes strings through unchanged.
  """
  def humanize_status(nil), do: nil
  def humanize_status(value) when is_binary(value), do: value

  def humanize_status(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp reject_blank_values(pairs) do
    Enum.reject(pairs, fn {_label, value} -> blank?(value) end)
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false
end
