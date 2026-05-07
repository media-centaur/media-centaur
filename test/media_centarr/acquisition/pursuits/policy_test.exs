defmodule MediaCentarr.Acquisition.Pursuits.PolicyTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Pursuits.{Policy, Pursuit, Snapshot}

  defp build_snapshot(pursuit_overrides) do
    pursuit_attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          state: "active",
          attempt_count: 0,
          inserted_at: ~U[2026-04-01 00:00:00Z],
          updated_at: ~U[2026-04-01 00:00:00Z]
        },
        pursuit_overrides
      )

    %Snapshot{
      pursuit: struct(Pursuit, pursuit_attrs),
      latest_grab: nil,
      queue_state: :unknown,
      now: ~U[2026-04-10 00:00:00Z]
    }
  end

  describe "evaluate/1 — terminal states" do
    test "satisfied returns :no_action" do
      snapshot = build_snapshot(%{state: "satisfied"})
      assert Policy.evaluate(snapshot) == :no_action
    end

    test "exhausted returns :no_action" do
      snapshot = build_snapshot(%{state: "exhausted"})
      assert Policy.evaluate(snapshot) == :no_action
    end

    test "cancelled returns :no_action" do
      snapshot = build_snapshot(%{state: "cancelled"})
      assert Policy.evaluate(snapshot) == :no_action
    end
  end

  describe "evaluate/1 — needs_decision" do
    test "needs_decision returns :no_action (waiting on user)" do
      snapshot = build_snapshot(%{state: "needs_decision"})
      assert Policy.evaluate(snapshot) == :no_action
    end
  end

  describe "evaluate/1 — exhaustion" do
    test "fewer than max attempts returns :no_action" do
      snapshot =
        build_snapshot(%{
          state: "active",
          attempt_count: 2,
          inserted_at: ~U[2026-04-01 00:00:00Z]
        })

      assert Policy.evaluate(snapshot) == :no_action
    end

    test "max attempts but pursuit too young returns :no_action" do
      snapshot =
        build_snapshot(%{
          state: "active",
          attempt_count: 4,
          inserted_at: ~U[2026-04-09 00:00:00Z]
        })

      assert Policy.evaluate(snapshot) == :no_action
    end

    test "max attempts AND pursuit older than the deadline returns {:exhaust, :max_attempts}" do
      snapshot =
        build_snapshot(%{
          state: "active",
          attempt_count: 4,
          inserted_at: ~U[2026-04-01 00:00:00Z]
        })

      assert Policy.evaluate(snapshot) == {:exhaust, :max_attempts}
    end

    test "more than max attempts AND old enough returns {:exhaust, :max_attempts}" do
      snapshot =
        build_snapshot(%{
          state: "active",
          attempt_count: 7,
          inserted_at: ~U[2026-04-01 00:00:00Z]
        })

      assert Policy.evaluate(snapshot) == {:exhaust, :max_attempts}
    end
  end

  describe "purity" do
    test "evaluate/1 produces the same output for the same input" do
      snapshot = build_snapshot(%{attempt_count: 4, inserted_at: ~U[2026-04-01 00:00:00Z]})
      assert Policy.evaluate(snapshot) == Policy.evaluate(snapshot)
    end
  end
end
