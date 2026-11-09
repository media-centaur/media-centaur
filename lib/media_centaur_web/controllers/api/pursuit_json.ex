defmodule MediaCentaurWeb.Api.PursuitJSON do
  @moduledoc "The JSON views of a pursuit: as one row of a list, and in full."

  alias MediaCentaur.Acquisition.Pursuits.Pursuit
  alias MediaCentaur.Acquisition.ViewModels.{CurrentAction, PursuitRow, PursuitStatus}

  def summary(%Pursuit{} = pursuit), do: %{id: pursuit.id, title: pursuit.title, state: pursuit.state}

  def row(%PursuitRow{} = row) do
    %{
      id: row.id,
      title: row.title,
      state: row.state,
      updated_at: row.updated_at,
      season_number: row.season_number,
      episode_number: row.episode_number,
      release_title: row.release_title,
      status: status(row.status),
      awaiting_decision: row.awaiting_decision?,
      units_wanted: row.units_wanted,
      units_satisfied: row.units_satisfied
    }
  end

  def detail(%PursuitStatus{} = status) do
    units = Enum.map(status.units, &unit(&1, status.targets))

    %{
      id: status.pursuit_id,
      title: status.pursuit.title,
      state: status.state,
      origin: status.origin,
      status: status(status.current_action),
      available_actions: status.available_actions,
      awaiting_decision: Enum.any?(units, & &1.awaiting_decision),
      units_wanted: max(length(units), 1),
      units_satisfied: Enum.count(units, &(&1.state == "satisfied")),
      last_activity_at: status.last_activity_at,
      units: units,
      downloads: Enum.map(status.downloads, &download/1)
    }
  end

  defp status(%CurrentAction{} = action), do: Map.take(action, [:verb, :description, :severity])

  defp unit(unit, targets) do
    target = Map.get(targets, unit.current_target_id)

    %{
      label: unit.label,
      state: unit.state,
      season_number: unit.season_number,
      episode_number: unit.episode_number,
      awaiting_decision: not is_nil(unit.awaiting_decision_at),
      release_title: target && target.release_title
    }
  end

  defp download(%{download: progress, release_title: release_title}) do
    progress
    |> Map.take([:state, :progress_pct, :size_bytes, :size_left_bytes, :eta, :protocol])
    |> Map.put(:release_title, release_title)
  end
end
