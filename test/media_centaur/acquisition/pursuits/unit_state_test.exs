defmodule MediaCentaur.Acquisition.Pursuits.UnitStateTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.{Unit, UnitState}

  describe "buckets and predicates" do
    test "active is the only in-flight state" do
      assert UnitState.in_flight?("active")
      assert UnitState.in_flight?(:active)
      refute UnitState.in_flight?("satisfied")
      assert UnitState.in_flight() == ["active"]
    end

    test "satisfied, exhausted, cancelled are terminal" do
      for state <- ~w(satisfied exhausted cancelled) do
        assert UnitState.terminal?(state)
      end

      refute UnitState.terminal?("active")
    end

    test "bucket/1 classifies every unit state" do
      assert UnitState.bucket("active") == :in_flight
      assert UnitState.bucket("satisfied") == :terminal_success
      assert UnitState.bucket("exhausted") == :terminal_failure
      assert UnitState.bucket("cancelled") == :terminal_failure
    end

    test "bucket/1 raises on an unknown state" do
      assert_raise ArgumentError, fn -> UnitState.bucket("partial") end
    end
  end

  describe "awaiting_decision?/1" do
    test "true only when the timestamp is set" do
      refute UnitState.awaiting_decision?(%Unit{awaiting_decision_at: nil})
      assert UnitState.awaiting_decision?(%Unit{awaiting_decision_at: DateTime.utc_now(:second)})
    end
  end
end
