defmodule MediaCentarr.Acquisition.Pursuits.StateTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.State

  describe "all/0" do
    test "lists every valid state as a DB string" do
      assert State.all() == ~w(active needs_decision satisfied exhausted cancelled)
    end
  end

  describe "in_flight/0" do
    test "lists states where the pursuit is still pursuing its goal" do
      assert State.in_flight() == ~w(active needs_decision)
    end
  end

  describe "terminal/0" do
    test "lists every terminal state" do
      assert State.terminal() == ~w(satisfied exhausted cancelled)
    end
  end

  describe "in_flight?/1" do
    test "true for active and needs_decision" do
      assert State.in_flight?("active")
      assert State.in_flight?(:active)
      assert State.in_flight?("needs_decision")
      assert State.in_flight?(:needs_decision)
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

    test "false for in-flight states" do
      refute State.terminal?("active")
      refute State.terminal?("needs_decision")
    end
  end

  describe "bucket/1" do
    test "active and needs_decision are :in_flight" do
      assert State.bucket("active") == :in_flight
      assert State.bucket("needs_decision") == :in_flight
    end

    test "satisfied is :terminal_success" do
      assert State.bucket("satisfied") == :terminal_success
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
end
