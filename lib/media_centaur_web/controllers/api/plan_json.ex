defmodule MediaCentaurWeb.Api.PlanJSON do
  @moduledoc "The JSON view of a plan and the releases it chose."

  alias MediaCentaur.Acquisition.Plans
  alias MediaCentaur.Acquisition.Plans.{Plan, PlanUnit}
  alias MediaCentaur.Search.Quality

  def plan(%Plan{} = plan) do
    %{
      id: plan.id,
      status: plan.status,
      approval_policy: plan.approval_policy,
      tmdb_id: String.to_integer(plan.tmdb_id),
      media_type: plan.tmdb_type,
      title: plan.title,
      year: plan.year,
      pursuit_id: plan.pursuit_id,
      error: plan.error,
      clean: Plans.clean?(plan),
      awaiting_approval: Plans.awaiting_approval?(plan),
      units: plan.id |> Plans.units_for() |> Enum.map(&unit/1)
    }
  end

  defp unit(%PlanUnit{} = unit) do
    %{
      season_number: unit.season_number,
      episode_number: unit.episode_number,
      label: unit.label,
      status: unit.status,
      release: release(unit)
    }
  end

  defp release(%PlanUnit{assigned_guid: nil}), do: nil

  defp release(%PlanUnit{} = unit) do
    %{
      guid: unit.assigned_guid,
      title: unit.assigned_title,
      quality: Quality.parse(unit.assigned_title),
      size_bytes: unit.assigned_size_bytes,
      seeders: unit.assigned_seeders
    }
  end
end
