defmodule MediaCentaur.Search.CourQueries do
  @moduledoc """
  Run-shaped search queries for a *later* broadcast run (cour).

  When the residual units belong to a run after the first, the
  first-run `"{title} Season {n}"` query is wrong — it surfaces the
  first-run pack the coverage guard already refused. This module emits
  the queries that describe the later run instead, ordered best-to-worst
  so the search worker tries each until one yields acceptable results:

    1. absolute episode range — `"{title} 29-38"` / `"{title} - 29"`
       (the most reliable; scene packs of a later cour name the absolute
       episode span)
    2. ordinal-season guesses — `"{title} 2nd Season"`,
       `"{title} Season 2"` (a cour is often released as its own
       "season N")
    3. TMDB-numbered range — `"{title} S01E29-E38"`

  Input is a run map (`%{index:, first_ep:, last_ep:}`, as produced by
  `Acquisition.CourSegmentation`); the ordinal is `index + 1`. The first
  run (index 0) is not cour-shaped — `build/2` returns `[]` for it (the
  regular ladder already covers run one). Pure module — no I/O, no DB.

  Lives in Search (a query-string concern, like `QueryBuilder`); the run
  map is plain data so Search stays independent of Acquisition.
  """

  alias MediaCentaur.Format

  @type run :: %{
          index: non_neg_integer(),
          first_ep: {integer(), integer()},
          last_ep: {integer(), integer()}
        }
  @type query :: {String.t(), keyword()}

  @spec build(String.t(), run()) :: [query()]
  def build(_title, %{index: 0}), do: []

  def build(title, %{index: index, first_ep: {season, first}, last_ep: {_season, last}}) do
    ordinal = index + 1

    [
      absolute_query(title, first, last),
      {"#{title} #{ordinal_word(ordinal)} Season", []},
      {"#{title} Season #{ordinal}", []},
      tmdb_query(title, season, first, last)
    ]
  end

  defp absolute_query(title, episode, episode), do: {"#{title} - #{episode}", []}
  defp absolute_query(title, first, last), do: {"#{title} #{first}-#{last}", []}

  defp tmdb_query(title, season, episode, episode) do
    {"#{title} S#{Format.pad2(season)}E#{Format.pad2(episode)}", []}
  end

  defp tmdb_query(title, season, first, last) do
    {"#{title} S#{Format.pad2(season)}E#{Format.pad2(first)}-E#{Format.pad2(last)}", []}
  end

  @doc """
  English ordinal word: 1 → "1st", 2 → "2nd", 3 → "3rd", 4 → "4th" …
  with the 11/12/13 exception. Shared with `CourCoverage`, which matches
  the same wording. Cours rarely exceed single digits, but the rule is
  general so it never reads "12nd".
  """
  @spec ordinal_word(pos_integer()) :: String.t()
  def ordinal_word(number) do
    suffix =
      cond do
        rem(number, 100) in 11..13 -> "th"
        rem(number, 10) == 1 -> "st"
        rem(number, 10) == 2 -> "nd"
        rem(number, 10) == 3 -> "rd"
        true -> "th"
      end

    "#{number}#{suffix}"
  end
end
