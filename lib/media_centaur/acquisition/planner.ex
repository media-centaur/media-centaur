defmodule MediaCentaur.Acquisition.Planner do
  @moduledoc """
  The coverage optimizer (media-search campaign Phase 3): maps wanted
  units to release candidates, applying the campaign's settled
  objective hierarchy

      Coverage → User preference → Consolidation → Health

  and the automatic granularity ladder (complete series → season range
  → season pack → episode span → single episode). The user picks
  *what* they want; this module picks *how*.

  ## Algorithm

  Acceptability-filter the options (quality bounds — best-available-now
  has **no** patience window), then resolve broad-first: for each
  multi-unit option, compare it against the ensemble of per-unit best
  picks restricted to the option's covered span —

  1. **Coverage**: whichever covers more of the span's wanted units
     wins outright (a pack with holes never beats singles that fill
     them, and singles with holes never beat a pack that fills them).
  2. **User preference**: equal coverage → higher summed quality rank
     wins (acceptable 4K singles beat an acceptable 1080p pack).
  3. **Consolidation**: equal quality → fewer grabs wins (the pack).
  4. **Health**: equal grabs → more seeders wins.

  Winning consolidations claim their covered units; remaining units get
  their per-unit best; units nothing acceptable covers come back as
  `unfound` — search results, never pursuit leaves (campaign hard
  boundary).

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
  # Consolidation pass — broad scopes first, each judged against the
  # per-unit-best ensemble over its own span.
  # ---------------------------------------------------------------------------

  defp consolidate(wanted, options) do
    options
    |> Enum.filter(&multi_unit?(&1, wanted))
    |> Enum.sort_by(&{-breadth(&1.scope), -quality_rank(&1), -seeders(&1)})
    |> Enum.reduce({[], wanted}, fn option, {assignments, remaining} ->
      covered = ReleaseCoverage.covered_units(option.scope, remaining)

      if length(covered) > 1 and beats_ensemble?(option, covered, remaining, options) do
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

  # Objective comparison of one consolidating option against the best
  # per-unit picks over the option's covered span.
  defp beats_ensemble?(option, covered, remaining, options) do
    span = ReleaseCoverage.covered_units(option.scope, remaining)

    ensemble =
      span
      |> Enum.map(&best_single_for(&1, options, option))
      |> Enum.reject(&is_nil/1)

    ensemble_covered = Enum.map(ensemble, fn {unit, _option} -> unit end)

    cond do
      # 1. Coverage — more of the span covered wins outright.
      length(covered) != length(ensemble_covered) ->
        length(covered) > length(ensemble_covered)

      # 2. User preference — higher summed quality rank wins.
      quality_rank(option) * length(covered) !=
          Enum.sum(Enum.map(ensemble, fn {_unit, o} -> quality_rank(o) end)) ->
        quality_rank(option) * length(covered) >
          Enum.sum(Enum.map(ensemble, fn {_unit, o} -> quality_rank(o) end))

      # 3. Consolidation — one grab beats N distinct grabs.
      distinct_grabs(ensemble) > 1 ->
        true

      # 4. Health — seeders decide between single-grab equals.
      true ->
        seeders(option) >= max_seeders(ensemble)
    end
  end

  # The best alternative provider for one unit, excluding the option
  # under judgement (it can't be its own competition).
  defp best_single_for(unit, options, judged_option) do
    options
    |> Enum.reject(&(&1 == judged_option))
    |> Enum.filter(fn %Option{scope: scope} ->
      ReleaseCoverage.covers?(scope, elem(unit, 0), elem(unit, 1))
    end)
    |> Enum.max_by(&{quality_rank(&1), seeders(&1)}, fn -> nil end)
    |> case do
      nil -> nil
      best -> {unit, best}
    end
  end

  defp distinct_grabs(ensemble) do
    ensemble |> Enum.map(fn {_unit, option} -> option.result.guid end) |> Enum.uniq() |> length()
  end

  defp max_seeders([]), do: 0
  defp max_seeders(ensemble), do: ensemble |> Enum.map(fn {_unit, o} -> seeders(o) end) |> Enum.max()

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
