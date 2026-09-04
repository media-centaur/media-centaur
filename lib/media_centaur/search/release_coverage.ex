defmodule MediaCentaur.Search.ReleaseCoverage do
  @moduledoc """
  Classifies a release title's **coverage scope** — which wanted units
  (season/episode pairs) the release would satisfy if grabbed. The
  granularity axis of the media-search coverage ladder (ADR-055 /
  media-search campaign Phase 2): complete series → season range →
  season pack → episode span → single episode.

  ## Classification syntax

  | shape | example | result |
  |---|---|---|
  | single episode | `Sample.Show.S01E03.1080p` | `{:episode, 1, 3}` |
  | episode span | `Sample.Show.S01E01-E05.1080p` | `{:episodes, 1, 1, 5}` |
  | season pack | `Sample.Show.S02.COMPLETE.1080p` | `{:season, 2}` |
  | season range | `Sample.Show.S01-S05.1080p` | `{:seasons, 1, 5}` |
  | complete series | `Sample.Show.COMPLETE.1080p` | `:series` |
  | anything else | `Sample.Movie.2010.1080p` | `:unknown` |

  False positives grab the wrong thing and false negatives never fall
  back (campaign risk #3) — classification is deliberately
  conservative: inverted ranges are `:unknown`, and `COMPLETE` only
  reads as a series pack when no season-scoped token is present.

  `covers?/3` and `covered_units/2` are the pack→episode accounting
  primitives (campaign risk #1): one pack satisfies many wanted units;
  a *partial* want list (units the library already has are simply not
  in the list) is the normal case, not an edge case.

  Pure module — no I/O, no DB. Title *identity* (is this even the right
  show?) is `TitleMatcher`'s job; this module only reads scope.
  """

  alias MediaCentaur.Format

  @type t ::
          {:episode, pos_integer(), pos_integer()}
          | {:episodes, pos_integer(), pos_integer(), pos_integer()}
          | {:season, pos_integer()}
          | {:seasons, pos_integer(), pos_integer()}
          | :series
          | :unknown

  @type unit :: {pos_integer(), pos_integer()}

  # Order matters: most-specific shapes first, so `S01E01-E05` never
  # half-matches as `S01`, and `S01-S05` is tested before bare `S01`.
  # The en-dash alternative `(?:-|–)` matches the literal multi-byte
  # en-dash sequence; a char class `[-–]` would compile in byte mode
  # (no `/u`) and match only the first byte, so `S01E01–E05` never
  # classified and silently fell to a narrower scope.
  @episode_span ~r/\bS(\d{1,2})[\s._-]?E(\d{1,3})(?:-|–)E?(\d{1,3})\b/i
  @single_episode ~r/\bS(\d{1,2})[\s._-]?E(\d{1,3})\b/i
  @season_range ~r/\bS(\d{1,2})[\s._-]?(?:-|–)[\s._-]?S?(\d{1,2})\b/i
  @season_marker ~r/\bS(\d{1,2})\b/i
  @season_wording ~r/\bSeason[\s._-]+(\d{1,2})\b/i
  @complete_marker ~r/\b(?:COMPLETE|Complete[\s._-]+(?:Series|Collection))\b/i

  @doc """
  The user-facing label for a coverage scope — what the plan board and
  the pursuit history call the release's slice. `:unknown` has none.
  """
  @spec scope_label(t()) :: String.t() | nil
  def scope_label({:episode, season, episode}), do: Format.episode_label(season, episode)

  def scope_label({:episodes, season, first, last}),
    do: "#{Format.episode_label(season, first)}-#{Format.pad2(last)}"

  def scope_label({:season, season}), do: "Season #{season} pack"
  def scope_label({:seasons, first, last}), do: "Seasons #{first}–#{last} pack"
  def scope_label(:series), do: "Complete series"
  def scope_label(:unknown), do: nil

  @doc "Classifies a release title into its coverage scope."
  @spec classify(String.t()) :: t()
  def classify(title) when is_binary(title) do
    cond do
      captures = run(@episode_span, title) ->
        [season, first_episode, last_episode] = captures

        if first_episode <= last_episode,
          do: {:episodes, season, first_episode, last_episode},
          else: :unknown

      captures = run(@single_episode, title) ->
        [season, episode] = captures
        {:episode, season, episode}

      captures = run(@season_range, title) ->
        [first_season, last_season] = captures
        if first_season <= last_season, do: {:seasons, first_season, last_season}, else: :unknown

      captures = run(@season_wording, title) ->
        [season] = captures
        {:season, season}

      captures = run(@season_marker, title) ->
        [season] = captures
        {:season, season}

      Regex.match?(@complete_marker, title) ->
        :series

      true ->
        :unknown
    end
  end

  @doc "True when the classified scope covers the `(season, episode)` unit."
  @spec covers?(t(), pos_integer(), pos_integer()) :: boolean()
  def covers?({:episode, season, episode}, season, episode), do: true
  def covers?({:episode, _season, _episode}, _wanted_season, _wanted_episode), do: false

  def covers?({:episodes, season, first, last}, season, episode)
      when episode >= first and episode <= last, do: true

  def covers?({:episodes, _season, _first, _last}, _wanted_season, _wanted_episode), do: false

  def covers?({:season, season}, season, _episode), do: true
  def covers?({:season, _season}, _wanted_season, _wanted_episode), do: false

  def covers?({:seasons, first, last}, season, _episode) when season >= first and season <= last,
    do: true

  def covers?({:seasons, _first, _last}, _wanted_season, _wanted_episode), do: false

  def covers?(:series, _season, _episode), do: true
  def covers?(:unknown, _season, _episode), do: false

  @doc """
  The wanted units this scope covers, in want order — the accounting
  primitive: one pack download satisfies every covered unit, and only
  those (campaign risk #1: never "done" with holes, never re-grab what
  a pack already brought).
  """
  @spec covered_units(t(), [unit()]) :: [unit()]
  def covered_units(scope, wanted_units) when is_list(wanted_units) do
    Enum.filter(wanted_units, fn {season, episode} -> covers?(scope, season, episode) end)
  end

  defp run(regex, title) do
    case Regex.run(regex, title, capture: :all_but_first) do
      nil -> nil
      captures -> Enum.map(captures, &String.to_integer/1)
    end
  end
end
