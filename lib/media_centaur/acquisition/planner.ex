defmodule MediaCentaur.Acquisition.Planner do
  @moduledoc """
  The coverage optimizer (media-search campaign Phase 3): maps wanted
  units to release candidates, applying the objective hierarchy

      Coverage → Consolidation → User preference → Health

  and the automatic granularity ladder (complete series → season range
  → season pack → episode span → single episode). The user picks
  *what* they want; this module picks *how*.

  ## Algorithm

  Acceptability-filter the options (quality bounds — best-available-now
  has **no** patience window), then consolidate broad-first: every
  multi-unit option still covering two or more remaining wanted units
  claims them, in `{breadth, quality, seeders}` order — so the widest
  acceptable consolidation wins its span, a 4K pack outranks a 1080p
  pack, and seeders break ties between equals. Remaining units get
  their per-unit best (quality, then seeders); units nothing acceptable
  covers come back as `unfound` — search results, never pursuit leaves
  (campaign hard boundary).

  **Within a span, consolidation outranks per-unit quality** (campaign
  plan-solver-consolidation, 2026-06-10 — supersedes the original
  summed-quality ensemble comparison): an acceptable pack is never
  fragmented into singles for a quality upgrade, because every claimed
  unit's higher-quality alternatives stay one click away in the plan
  board's swap picker, while overlapping grabs are unconditionally
  duplicate data. The retired comparison let one 4K single veto a
  whole season pack and then re-grab the pack anyway for the leftovers
  (7 grabs where 2 sufficed).

  Pure module — no I/O, no DB. Inputs are pre-verified: the plan runner
  is responsible for show-identity (`TitleMatcher.coverage/2`) and for
  filtering excluded releases before solving.
  """

  alias MediaCentaur.Search.{Quality, ReleaseCoverage, SearchResult}

  defmodule Option do
    @moduledoc "One identity-verified candidate: the release and its classified coverage scope."

    @enforce_keys [:result, :scope]
    defstruct [:result, :scope]

    @type t :: %__MODULE__{result: SearchResult.t(), scope: ReleaseCoverage.t()}
  end

  defmodule Assignment do
    @moduledoc "One chosen release and the wanted units it satisfies."

    @enforce_keys [:result, :scope, :units]
    defstruct [:result, :scope, :units]

    @type t :: %__MODULE__{
            result: SearchResult.t(),
            scope: ReleaseCoverage.t(),
            units: [ReleaseCoverage.unit()]
          }
  end

  defmodule Solution do
    @moduledoc "The solved plan: assignments plus the units nothing acceptable covers."

    @enforce_keys [:assignments, :unfound]
    defstruct [:assignments, :unfound]

    @type t :: %__MODULE__{assignments: [Assignment.t()], unfound: [ReleaseCoverage.unit()]}
  end

  @type prefs :: %{min_quality: String.t(), max_quality: String.t()}

  @spec solve([ReleaseCoverage.unit()], [Option.t()], prefs()) :: Solution.t()
  def solve(wanted, options, prefs) when is_list(wanted) and is_list(options) do
    acceptable =
      Enum.filter(options, fn %Option{result: result} ->
        Quality.acceptable?(result.quality, prefs.min_quality, prefs.max_quality)
      end)

    {assignments, remaining} = consolidate(wanted, acceptable)
    {single_assignments, unfound} = assign_singles(remaining, acceptable)

    %Solution{
      assignments: assignments ++ single_assignments,
      unfound: unfound
    }
  end

  # ---------------------------------------------------------------------------
  # Consolidation pass — broad scopes first. Any option still covering
  # two or more remaining wanted units claims them; the sort order
  # (breadth, then quality, then seeders) IS the policy, so the better
  # pack is judged — and claims — first. No per-unit ensemble
  # comparison: fragmenting a span for quality is never automatic (see
  # moduledoc), and an option whose span has real holes only ever
  # claims what it covers — singles fill the rest in the next pass.
  # ---------------------------------------------------------------------------

  defp consolidate(wanted, options) do
    options
    |> Enum.filter(&multi_unit?(&1, wanted))
    |> Enum.sort_by(&{-breadth(&1.scope), -quality_rank(&1), -seeders(&1)})
    |> Enum.reduce({[], wanted}, fn option, {assignments, remaining} ->
      covered = ReleaseCoverage.covered_units(option.scope, remaining)

      if length(covered) > 1 do
        assignment = %Assignment{result: option.result, scope: option.scope, units: covered}
        {[assignment | assignments], remaining -- covered}
      else
        {assignments, remaining}
      end
    end)
    |> then(fn {assignments, remaining} -> {Enum.reverse(assignments), remaining} end)
  end

  defp multi_unit?(%Option{scope: scope}, wanted) do
    scope |> ReleaseCoverage.covered_units(wanted) |> length() > 1
  end

  # ---------------------------------------------------------------------------
  # Singles pass — best remaining provider per unit.
  # ---------------------------------------------------------------------------

  defp assign_singles(remaining, options) do
    {by_option, unfound} =
      Enum.reduce(remaining, {%{}, []}, fn {season, episode} = unit, {by_option, unfound} ->
        provider =
          options
          |> Enum.filter(fn %Option{scope: scope} -> ReleaseCoverage.covers?(scope, season, episode) end)
          |> Enum.max_by(&{quality_rank(&1), seeders(&1)}, fn -> nil end)

        case provider do
          nil -> {by_option, [unit | unfound]}
          option -> {Map.update(by_option, option, [unit], &[unit | &1]), unfound}
        end
      end)

    assignments =
      Enum.map(by_option, fn {option, units} ->
        %Assignment{result: option.result, scope: option.scope, units: Enum.reverse(units)}
      end)

    {assignments, Enum.reverse(unfound)}
  end

  # ---------------------------------------------------------------------------

  defp breadth(:series), do: 4
  defp breadth({:seasons, _first, _last}), do: 3
  defp breadth({:season, _season}), do: 2
  defp breadth({:episodes, _season, _first, _last}), do: 1
  defp breadth({:episode, _season, _episode}), do: 0

  defp quality_rank(%Option{result: %SearchResult{quality: quality}}), do: Quality.rank(quality)

  defp seeders(%Option{result: %SearchResult{seeders: seeders}}), do: seeders || 0
end
