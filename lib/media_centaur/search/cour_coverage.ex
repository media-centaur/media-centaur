defmodule MediaCentaur.Search.CourCoverage do
  @moduledoc """
  Run-aware coverage classification for a later broadcast run (cour).

  `Search.ReleaseCoverage` classifies a title context-free, so it cannot
  map `"Title 2nd Season"` or `"Title 29-38"` to a TMDB episode range —
  that needs to know *which* run those tokens describe. This module does
  the contextual join: given the run (a `CourSegmentation` run map) and
  the show title, it recognizes the run's pack-name forms and returns the
  episode scope they cover (`{:episodes, season, first, last}`, or
  `{:episode, …}` for a one-episode run), else `:no_match`.

  Recognized forms (identity must match first, so a different show with
  the right tokens is rejected):

    * ordinal-season wording matching the run ordinal — `"2nd Season"`,
      `"Season 2"` for the second run
    * the run's absolute episode range — `29-38` (hyphen or en-dash)

  TMDB-numbered packs (`SxxEyy-Ezz`) need no run context — plain
  `ReleaseCoverage` already classifies those, so they are out of scope
  here. The first run (index 0) is never cour-classified.

  Later-cour naming is fuzzy, so callers treat what this returns as an
  **offer** for the user to confirm, never an auto-grab. Pure module —
  no I/O, no DB. The run map is plain data, so Search stays independent
  of Acquisition.
  """

  alias MediaCentaur.Search.{CourQueries, ReleaseCoverage}

  @spec classify(String.t(), String.t(), CourQueries.run()) :: ReleaseCoverage.t() | :no_match
  def classify(_title, _show_title, %{index: 0}), do: :no_match

  def classify(title, show_title, %{index: index, first_ep: {season, first}, last_ep: {_s, last}})
      when is_binary(title) do
    if identity_matches?(title, show_title) and run_token?(title, index + 1, first, last) do
      scope(season, first, last)
    else
      :no_match
    end
  end

  defp scope(season, episode, episode), do: {:episode, season, episode}
  defp scope(season, first, last), do: {:episodes, season, first, last}

  # The normalized title must begin with the normalized show title — the
  # run tokens follow it. Cheap, and enough to reject a different show.
  defp identity_matches?(title, show_title) do
    String.starts_with?(normalize(title), normalize(show_title))
  end

  defp run_token?(title, ordinal, first, last) do
    ordinal_season?(title, ordinal) or absolute_range?(title, first, last)
  end

  defp ordinal_season?(title, ordinal) do
    word = CourQueries.ordinal_word(ordinal)

    Regex.match?(~r/\bseason[\s._-]*#{ordinal}\b/i, title) or
      Regex.match?(~r/\b#{word}[\s._-]+season\b/i, title)
  end

  # The en-dash alternative is written `(?:-|–)`, not a `[-–]` class: a
  # char class compiles in byte mode (no `/u`) and would match only the
  # first byte of the multi-byte en-dash (the ReleaseCoverage trap).
  defp absolute_range?(title, episode, episode) do
    Regex.match?(~r/(?:-|–)[\s._]*#{episode}(?!\d)/, title)
  end

  defp absolute_range?(title, first, last) do
    Regex.match?(~r/(?<!\d)#{first}[\s._]*(?:-|–)[\s._]*#{last}(?!\d)/, title)
  end

  defp normalize(string) do
    string
    |> String.downcase()
    |> String.replace(~r/[._]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
