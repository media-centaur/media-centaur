defmodule MediaCentaur.Acquisition.Plans.Board do
  @moduledoc """
  Builds the `ViewModels.PlanBoard` for a draft plan — the manifest
  (UIDR-029 as amended 2026-11-06): release lines first, ordered by
  their first episode, then the outcome lines — searching, lower
  quality only, not found, pack offers, dropped — each carrying the
  cells that share it. `build/1` reads the units once through
  `Plans.units_for/1` and hands them to `assemble/2`, the pure
  projection stories and unit tests call directly. Owns no state.
  """

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard

  @doc "Builds the board for a plan: one units query, then `assemble/2`."
  @spec build(Plan.t()) :: PlanBoard.t()
  def build(%Plan{} = plan), do: assemble(plan, Plans.units_for(plan.id))

  @doc """
  Projects a plan and its units into the board. Pure.

  Release lines come first, ordered by the first episode each covers;
  then, in this order and only when they have cells: the searching line
  (a planning plan's pending units), the below-preference line, the
  not-found line, one offer line per pack the planner set aside, the
  dropped line (excluded units). Each outcome line's cells are grouped
  by season in episode order.
  """
  @spec assemble(Plan.t(), [PlanUnit.t()]) :: PlanBoard.t()
  def assemble(%Plan{} = plan, units) when is_list(units) do
    planning? = plan.status == "planning"
    cells = Map.new(units, &{&1.id, cell(&1, planning?)})
    found = Enum.filter(units, &(&1.status == "found"))

    %PlanBoard{
      plan_id: plan.id,
      title: plan.title,
      status: String.to_existing_atom(plan.status),
      error: plan.error,
      wanted: Enum.count(units, &(&1.status != "excluded")),
      covered: length(found),
      lines: release_lines(found, cells) ++ outcome_lines(units, cells, planning?),
      movie?: plan.tmdb_type == "movie",
      lower_quality_accepted?: lower_quality_accepted?(plan)
    }
  end

  # -- release lines -----------------------------------------------------------

  defp release_lines(found, cells) do
    releases =
      found
      |> Enum.group_by(& &1.assigned_guid)
      |> Enum.map(fn {guid, group} ->
        [first | _] = Enum.sort_by(group, & &1.position)

        release = %PlanBoard.Release{
          guid: guid,
          title: first.assigned_title,
          scope_label: first.assigned_scope,
          quality: first.assigned_quality,
          seeders: first.assigned_seeders,
          size_bytes: first.assigned_size_bytes,
          units_count: length(group),
          swap_unit_id: first.id
        }

        {release, rows(group, cells)}
      end)

    claims = Enum.group_by(found, & &1.assigned_guid, &{&1.season_number, &1.episode_number})

    overlaps =
      releases
      |> Enum.map(&elem(&1, 0))
      |> PlanBoard.overlaps(claims)
      |> Map.new(&{&1.exclude_guid, &1})

    releases
    |> Enum.map(fn {release, rows} ->
      %PlanBoard.Line{
        id: "release-#{:erlang.phash2(release.guid)}",
        kind: :release,
        rows: rows,
        release: %{release | overlap: Map.get(overlaps, release.guid)}
      }
    end)
    |> Enum.sort_by(&first_cell_order/1)
  end

  defp first_cell_order(%PlanBoard.Line{} = line) do
    case PlanBoard.Line.cells(line) do
      [first | _] -> {first.season_number || 0, first.episode_number || 0}
      [] -> {0, 0}
    end
  end

  # -- outcome lines -----------------------------------------------------------

  defp outcome_lines(units, cells, planning?) do
    searching = if planning?, do: Enum.filter(units, &(&1.status == "pending")), else: []
    below = Enum.filter(units, &(&1.status == "unfound" and &1.below_floor_count > 0))

    not_found =
      Enum.filter(
        units,
        &((&1.status == "unfound" and &1.below_floor_count == 0 and is_nil(&1.offered_guid)) or
            (&1.status == "pending" and not planning?))
      )

    offered = Enum.filter(units, &(&1.status == "unfound" and not is_nil(&1.offered_guid)))
    excluded = Enum.filter(units, &(&1.status == "excluded"))

    Enum.reject(
      [
        line("searching", :searching, searching, cells),
        line("lower-quality", :below_preference, below, cells, below: below_preference(below)),
        line("not-found", :not_found, not_found, cells)
      ] ++
        offer_lines(offered, cells) ++
        [line("dropped", :excluded, excluded, cells)],
      &is_nil/1
    )
  end

  # Unfound units for which lower-quality releases exist (the planner's
  # solve-time verdict), totalled into one grouped summary (UIDR-029) —
  # never a bare "not available" gap. Candidates are listed live via
  # `Plans.Alternatives.for_unit/1`; taking them is the explicit per-title
  # acceptance (`Plans.accept_lower_quality/1`).
  defp below_preference([]), do: nil

  defp below_preference([only]) do
    %PlanBoard.BelowPreference{
      units: 1,
      releases: only.below_floor_count,
      unit_id: only.id,
      unit_label: only.label
    }
  end

  defp below_preference(below_units) do
    %PlanBoard.BelowPreference{
      units: length(below_units),
      releases: below_units |> Enum.map(& &1.below_floor_count) |> Enum.sum()
    }
  end

  # Unfound units whose only coverage is an over-broad pack the planner
  # set aside (fit gating) — surfaced as an explicit opt-in, never an
  # auto-grab. One line per pack (a pack covering several unfound units is
  # one grab); the CTA reuses the swap-picker's `choose_release` path,
  # which claims every unit the pack covers.
  defp offer_lines(offered, cells) do
    offered
    |> Enum.group_by(& &1.offered_guid)
    |> Enum.map(fn {guid, group} ->
      [first | _] = Enum.sort_by(group, & &1.position)

      offer = %PlanBoard.Offer{
        unit_id: first.id,
        unit_label: offer_label(group),
        guid: guid,
        scope_label: first.offered_scope,
        title: first.offered_title,
        size_bytes: first.offered_size_bytes
      }

      line("offer-#{:erlang.phash2(guid)}", :offer, group, cells, offer: offer)
    end)
    |> Enum.sort_by(&first_cell_order/1)
  end

  defp offer_label([unit]), do: unit.label
  defp offer_label(group), do: "#{length(group)} episodes"

  defp line(id, kind, units, cells, extra \\ [])
  defp line(_id, _kind, [], _cells, _extra), do: nil

  defp line(id, kind, units, cells, extra) do
    struct!(%PlanBoard.Line{id: id, kind: kind, rows: rows(units, cells)}, extra)
  end

  # -- cells -------------------------------------------------------------------

  defp rows(units, cells) do
    units
    |> Enum.map(&Map.fetch!(cells, &1.id))
    |> Enum.group_by(& &1.season_number)
    |> Enum.sort_by(fn {season, _cells} -> season || 0 end)
    |> Enum.map(fn {season, season_cells} ->
      %PlanBoard.SeasonRow{
        season_number: season,
        cells: Enum.sort_by(season_cells, &(&1.episode_number || 0))
      }
    end)
  end

  defp cell(%PlanUnit{} = unit, planning?) do
    %PlanBoard.Cell{
      plan_unit_id: unit.id,
      season_number: unit.season_number,
      episode_number: unit.episode_number,
      label: unit.label,
      state: cell_state(unit, planning?),
      release_guid: unit.assigned_guid,
      release_title: unit.assigned_title
    }
  end

  defp cell_state(%PlanUnit{status: "found"}, _planning?), do: :assigned

  defp cell_state(%PlanUnit{status: "unfound", below_floor_count: count}, _planning?) when count > 0,
    do: :below_preference

  defp cell_state(%PlanUnit{status: "unfound"}, _planning?), do: :unfound
  defp cell_state(%PlanUnit{status: "excluded"}, _planning?), do: :excluded
  defp cell_state(%PlanUnit{status: "pending"}, true), do: :searching
  defp cell_state(%PlanUnit{status: "pending"}, false), do: :unfound

  defp lower_quality_accepted?(%Plan{criteria: criteria}) do
    (criteria || %{})["min_quality"] == "any"
  end
end
