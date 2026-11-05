defmodule MediaCentaur.Showcase.AcquisitionRows do
  @moduledoc """
  Inserts a showcase pursuit with its current target, unit and coverage
  row, bypassing changeset validations so a seeded row can land in any
  terminal or intermediate state directly. Real transitions flow through
  the acquisition context's changesets; this is seed data only, used by
  `MediaCentaur.Showcase` (the Downloads activity) and
  `MediaCentaur.Showcase.ReviewScenarios` (a grab whose file the search
  contradicts).
  """

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, TargetUnit, Unit}
  alias MediaCentaur.Acquisition.Target
  alias MediaCentaur.Repo

  @spec insert!(pursuit_attrs: map(), target_attrs: map()) :: Pursuit.t()
  def insert!(pursuit_attrs: p_attrs, target_attrs: t_attrs) do
    now = DateTime.utc_now(:second)
    pursuit_base = Map.merge(%{inserted_at: now, updated_at: now}, p_attrs)

    pursuit =
      %Pursuit{}
      |> Ecto.Changeset.change(pursuit_base)
      |> Repo.insert!()

    target_base = Map.merge(t_attrs, %{pursuit_id: pursuit.id, inserted_at: now, updated_at: now})

    target_base =
      case t_attrs[:status] do
        "acquired" -> Map.put_new(target_base, :acquired_at, now)
        "failed" -> Map.put_new(target_base, :cancelled_at, now)
        "cancelled" -> Map.put_new(target_base, :cancelled_at, now)
        _ -> target_base
      end

    target =
      %Target{}
      |> Ecto.Changeset.change(target_base)
      |> Repo.insert!()

    # The attempt thread lives on the unit (ADR-055): one unit mirroring
    # the pursuit's state, pointing at the target, plus the coverage row.
    unit =
      %Unit{}
      |> Ecto.Changeset.change(%{
        pursuit_id: pursuit.id,
        state: pursuit_base[:state] || "active",
        current_target_id: target.id,
        inserted_at: now,
        updated_at: now
      })
      |> Repo.insert!()

    %TargetUnit{}
    |> Ecto.Changeset.change(%{
      target_id: target.id,
      unit_id: unit.id,
      inserted_at: now,
      updated_at: now
    })
    |> Repo.insert!()

    pursuit
  end
end
