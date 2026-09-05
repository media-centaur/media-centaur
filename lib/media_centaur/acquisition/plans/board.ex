defmodule MediaCentaur.Acquisition.Plans.Board do
  @moduledoc """
  Builds the `ViewModels.PlanBoard` for a draft plan — the coverage
  board (UIDR-014): unit cells in season rows, the chosen releases
  grouped from the units' assignments, the gaps, offers and
  below-preference summary. Reads through `Plans.units_for/1`; owns
  no state.
  """

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Acquisition.ViewModels.PlanBoard

  @doc """
  Builds the `PlanBoard` view-model for the coverage board (UIDR-014):
  unit cells in season rows, the chosen releases grouped from the
  units' assignments, and the gaps. One units query.
  """
  @spec build(Plan.t()) :: PlanBoard.t()
  def build(%Plan{} = plan) do
    units = Plans.units_for(plan.id)
    planning? = plan.status == "planning"

    cells =
      Enum.map(units, fn unit ->
        %PlanBoard.Cell{
          plan_unit_id: unit.id,
          season_number: unit.season_number,
          episode_number: unit.episode_number,
          label: unit.label,
          state: cell_state(unit, planning?),
          release_guid: unit.assigned_guid,
          release_title: unit.assigned_title
        }
      end)

    seasons =
      cells
      |> Enum.group_by(& &1.season_number)
      |> Enum.sort_by(fn {season, _cells} -> season || 0 end)
      |> Enum.map(fn {season, season_cells} ->
        %PlanBoard.SeasonRow{
          season_number: season,
          cells: Enum.sort_by(season_cells, & &1.episode_number)
        }
      end)

    releases =
      units
      |> Enum.filter(&(&1.status == "found"))
      |> Enum.group_by(& &1.assigned_guid)
      |> Enum.map(fn {guid, group} ->
        [first | _] = Enum.sort_by(group, & &1.position)

        %PlanBoard.Release{
          guid: guid,
          title: first.assigned_title,
          scope_label: first.assigned_scope,
          quality: first.assigned_quality,
          seeders: first.assigned_seeders,
          size_bytes: first.assigned_size_bytes,
          units_count: length(group),
          swap_unit_id: first.id
        }
      end)
      |> Enum.sort_by(&(-&1.units_count))

    wanted = Enum.count(units, &(&1.status != "excluded"))
    covered = Enum.count(units, &(&1.status == "found"))

    claims =
      units
      |> Enum.filter(&(&1.status == "found"))
      |> Enum.group_by(& &1.assigned_guid, &{&1.season_number, &1.episode_number})

    %PlanBoard{
      plan_id: plan.id,
      title: plan.title,
      status: String.to_existing_atom(plan.status),
      error: plan.error,
      wanted: wanted,
      covered: covered,
      seasons: seasons,
      releases: releases,
      gaps:
        units
        |> Enum.filter(&(&1.status == "unfound" and &1.below_floor_count == 0))
        |> Enum.map(& &1.label),
      total_size_bytes: total_size(releases),
      movie?: plan.tmdb_type == "movie",
      lower_quality_accepted?: lower_quality_accepted?(plan),
      overlaps: PlanBoard.overlaps(releases, claims),
      offers: offers(units),
      below_preference: below_preference(units)
    }
  end

  # Unfound units for which lower-quality releases exist (the planner's
  # solve-time verdict), totalled into one grouped summary (UIDR-029) —
  # never a bare "not available" gap. Candidates are listed live via
  # `Plans.Alternatives.for_unit/1`; taking them is the explicit per-title
  # acceptance (`Plans.accept_lower_quality/1`).
  defp below_preference(units) do
    case for unit <- units, unit.status == "unfound", unit.below_floor_count > 0, do: unit do
      [] ->
        nil

      [only] ->
        %PlanBoard.BelowPreference{
          units: 1,
          releases: only.below_floor_count,
          unit_id: only.id,
          unit_label: only.label
        }

      below_units ->
        %PlanBoard.BelowPreference{
          units: length(below_units),
          releases: below_units |> Enum.map(& &1.below_floor_count) |> Enum.sum()
        }
    end
  end

  defp lower_quality_accepted?(%Plan{criteria: criteria}) do
    (criteria || %{})["min_quality"] == "any"
  end

  # Unfound units whose only coverage is an over-broad pack the planner
  # set aside (fit gating) — surfaced as an explicit opt-in, never an
  # auto-grab. One row per pack (a pack covering several unfound units is
  # one grab); the CTA reuses the swap-picker's `choose_release` path,
  # which claims every unit the pack covers.
  defp offers(units) do
    units
    |> Enum.filter(&(&1.status == "unfound" and not is_nil(&1.offered_guid)))
    |> Enum.group_by(& &1.offered_guid)
    |> Enum.map(fn {guid, group} ->
      [first | _] = Enum.sort_by(group, & &1.position)

      %PlanBoard.Offer{
        unit_id: first.id,
        unit_label: offer_label(group),
        guid: guid,
        scope_label: first.offered_scope,
        title: first.offered_title,
        size_bytes: first.offered_size_bytes
      }
    end)
    |> Enum.sort_by(& &1.unit_label)
  end

  defp offer_label([unit]), do: unit.label
  defp offer_label(group), do: "#{length(group)} episodes"

  defp total_size(releases) do
    sizes = releases |> Enum.map(& &1.size_bytes) |> Enum.filter(&is_integer/1)
    if sizes != [], do: Enum.sum(sizes)
  end

  defp cell_state(%PlanUnit{status: "found"}, _planning?), do: :assigned

  defp cell_state(%PlanUnit{status: "unfound", below_floor_count: count}, _planning?) when count > 0,
    do: :below_preference

  defp cell_state(%PlanUnit{status: "unfound"}, _planning?), do: :unfound
  defp cell_state(%PlanUnit{status: "excluded"}, _planning?), do: :excluded
  defp cell_state(%PlanUnit{status: "pending"}, true), do: :searching
  defp cell_state(%PlanUnit{status: "pending"}, false), do: :unfound
end
