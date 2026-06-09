defmodule MediaCentaur.Acquisition.Pursuits.UnitsTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.{Unit, Units}

  defp unit(attrs) do
    struct(
      %Unit{id: Ecto.UUID.generate(), state: "active", position: 0},
      attrs
    )
  end

  describe "lead_of/1 — which thread a pursuit-scoped surface shows/acts on" do
    test "prefers the active unit awaiting a decision" do
      awaiting = unit(%{awaiting_decision_at: DateTime.utc_now(:second), position: 2})

      units = [
        unit(%{current_target_id: Ecto.UUID.generate(), position: 0}),
        unit(%{position: 1}),
        awaiting
      ]

      assert Units.lead_of(units).id == awaiting.id
    end

    test "falls back to the first active unit with a current target" do
      with_target = unit(%{current_target_id: Ecto.UUID.generate(), position: 1})
      units = [unit(%{position: 0}), with_target]

      assert Units.lead_of(units).id == with_target.id
    end

    test "falls back to the first active unit, then the first unit at all" do
      active = unit(%{position: 1})
      units = [unit(%{state: "satisfied", position: 0}), active]
      assert Units.lead_of(units).id == active.id

      terminal_only = [
        unit(%{state: "satisfied", position: 0}),
        unit(%{state: "exhausted", position: 1})
      ]

      assert Units.lead_of(terminal_only).id == hd(terminal_only).id
    end

    test "terminal units never lead while an active one exists, even with a target" do
      satisfied_with_target =
        unit(%{state: "satisfied", current_target_id: Ecto.UUID.generate(), position: 0})

      active_bare = unit(%{position: 1})

      assert Units.lead_of([satisfied_with_target, active_bare]).id == active_bare.id
    end

    test "empty list yields nil" do
      assert Units.lead_of([]) == nil
    end
  end
end
