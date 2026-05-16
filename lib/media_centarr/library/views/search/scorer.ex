defmodule MediaCentarr.Library.Views.Search.Scorer do
  @moduledoc """
  Pure scoring function for the `Library.Views.Search` projection
  (ADR-041, Library Schema v2 Phase 3 Task C).

  Computes a `[0.0, 1.0]` match score between a normalised query and a
  normalised candidate string. Higher is better. The Search projection
  calls `score/2` inside an `:ets.foldl/3` over indexed entities; the
  caller sorts the resulting `{score, item}` pairs descending and slices
  to `:limit`.

  ## Normalisation contract

  Both `query` and `candidate` are expected to already be:

    * lowercased
    * trimmed of leading / trailing whitespace

  This module does not re-normalise — it assumes the caller has done so
  (cheapest place, computed once per row at index time). The only
  exception is the empty/whitespace short-circuit, which checks the raw
  string so a caller that forgets to trim still gets the zero result.

  ## Scoring rules (in priority order)

    1. Empty / whitespace query → `0.0` (no ranking signal).
    2. Exact match → `1.0`.
    3. Prefix match (candidate starts with query) →
       `0.7 + 0.29 * (query_length / candidate_length)`.
       Floor 0.7 for the degenerate single-character prefix; ceiling
       0.99 to keep prefix scores strictly below exact-match scores
       even when the candidate is one character longer than the query.
    4. Substring match (candidate contains query, not at index 0) →
       `0.4 + 0.3 * (query_length / candidate_length)`.
       Clamped to `[0.4, 0.7]`; strictly below the prefix score for the
       same `(query_length, candidate_length)` pair.
    5. Otherwise → `String.jaro_distance/2`, but only if `>= 0.92`;
       below that, `0.0`. The threshold is tight on purpose: Jaro
       reports `~0.9` for any two strings that share a long common
       prefix (`"movie a"` vs `"movie b"` scores 0.9047), which would
       cause an exact-match query to surface near-miss titles as
       fuzzy hits. 0.92 only admits single-character typos against
       the same word (`"mvoie"` vs `"movie"` scores 0.9333).

  The rule order matters: prefix is checked before substring so a query
  matching at index 0 takes the higher score.
  """

  @prefix_floor 0.7
  @prefix_ceiling 0.99
  @prefix_range 0.29

  @substring_floor 0.4
  @substring_ceiling 0.7
  @substring_range 0.3

  @jaro_threshold 0.92

  @doc """
  Score the normalised `query` against the normalised `candidate`. Both
  inputs are expected to already be downcased and trimmed (see
  *Normalisation contract* in the moduledoc).
  """
  @spec score(String.t(), String.t()) :: float()
  def score(query, candidate)

  def score(query, candidate) when not is_binary(query) or not is_binary(candidate), do: 0.0

  def score(query, candidate) do
    trimmed = String.trim(query)

    cond do
      trimmed == "" -> 0.0
      candidate == "" -> 0.0
      trimmed == candidate -> 1.0
      String.starts_with?(candidate, trimmed) -> prefix_score(trimmed, candidate)
      String.contains?(candidate, trimmed) -> substring_score(trimmed, candidate)
      true -> jaro_score(trimmed, candidate)
    end
  end

  defp prefix_score(query, candidate) do
    ratio = String.length(query) / String.length(candidate)
    raw = @prefix_floor + @prefix_range * ratio

    raw
    |> max(@prefix_floor)
    |> min(@prefix_ceiling)
  end

  defp substring_score(query, candidate) do
    ratio = String.length(query) / String.length(candidate)
    raw = @substring_floor + @substring_range * ratio

    raw
    |> max(@substring_floor)
    |> min(@substring_ceiling)
  end

  defp jaro_score(query, candidate) do
    distance = String.jaro_distance(query, candidate)

    if distance >= @jaro_threshold do
      distance
    else
      0.0
    end
  end
end
