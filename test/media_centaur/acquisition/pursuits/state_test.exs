defmodule MediaCentaur.Acquisition.Pursuits.StateTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.{Pursuit, State}

  describe "all/0" do
    test "lists every valid state as a DB string" do
      assert State.all() == ~w(active satisfied partial exhausted cancelled)
    end
  end

  describe "in_flight/0" do
    test "lists states where the pursuit is still pursuing its goal" do
      assert State.in_flight() == ~w(active)
    end
  end

  describe "terminal/0" do
    test "lists every terminal state" do
      assert State.terminal() == ~w(satisfied partial exhausted cancelled)
    end
  end

  describe "in_flight?/1" do
    test "true for active" do
      assert State.in_flight?("active")
      assert State.in_flight?(:active)
    end

    test "false for terminal states" do
      refute State.in_flight?("satisfied")
      refute State.in_flight?("exhausted")
      refute State.in_flight?("cancelled")
    end
  end

  describe "terminal?/1" do
    test "true for satisfied, exhausted, cancelled" do
      assert State.terminal?("satisfied")
      assert State.terminal?("exhausted")
      assert State.terminal?("cancelled")
    end

    test "false for active" do
      refute State.terminal?("active")
    end
  end

  describe "awaiting_decision?/1" do
    test "true when awaiting_decision_at is set" do
      pursuit = %Pursuit{awaiting_decision_at: DateTime.utc_now(:second)}
      assert State.awaiting_decision?(pursuit)
    end

    test "false when awaiting_decision_at is nil" do
      pursuit = %Pursuit{awaiting_decision_at: nil}
      refute State.awaiting_decision?(pursuit)
    end
  end

  describe "bucket/1" do
    test "active is :in_flight" do
      assert State.bucket("active") == :in_flight
    end

    test "satisfied and partial are :terminal_success" do
      assert State.bucket("satisfied") == :terminal_success
      assert State.bucket("partial") == :terminal_success
    end

    test "exhausted and cancelled are :terminal_failure" do
      assert State.bucket("exhausted") == :terminal_failure
      assert State.bucket("cancelled") == :terminal_failure
    end

    test "raises for unknown states" do
      assert_raise ArgumentError, fn -> State.bucket("nonsense") end
    end
  end

  describe "atom-or-string normalization" do
    test "predicates accept atoms and strings interchangeably" do
      assert State.in_flight?(:active) == State.in_flight?("active")
      assert State.terminal?(:satisfied) == State.terminal?("satisfied")
      assert State.bucket(:exhausted) == State.bucket("exhausted")
    end
  end

  describe "fold_units/1" do
    test "any active unit keeps the pursuit active" do
      assert State.fold_units(~w(active satisfied exhausted)) == "active"
      assert State.fold_units(~w(active)) == "active"
    end

    test "all units satisfied folds to satisfied" do
      assert State.fold_units(~w(satisfied)) == "satisfied"
      assert State.fold_units(~w(satisfied satisfied)) == "satisfied"
    end

    test "terminal with a mix of satisfied and not folds to partial" do
      assert State.fold_units(~w(satisfied exhausted)) == "partial"
      assert State.fold_units(~w(satisfied cancelled)) == "partial"
      assert State.fold_units(~w(satisfied exhausted cancelled)) == "partial"
    end

    test "terminal with no satisfaction and at least one exhausted folds to exhausted" do
      assert State.fold_units(~w(exhausted)) == "exhausted"
      assert State.fold_units(~w(exhausted cancelled)) == "exhausted"
    end

    test "all units cancelled folds to cancelled" do
      assert State.fold_units(~w(cancelled)) == "cancelled"
      assert State.fold_units(~w(cancelled cancelled)) == "cancelled"
    end

    test "raises on an empty unit list — a pursuit without units is a bug" do
      assert_raise ArgumentError, fn -> State.fold_units([]) end
    end
  end
end
