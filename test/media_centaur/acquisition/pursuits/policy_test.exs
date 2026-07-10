defmodule MediaCentaur.Acquisition.Pursuits.PolicyTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.Pursuits.{Policy, Pursuit, Snapshot, Thresholds, Unit}

  # The thread overrides (attempt_count, awaiting_decision_at,
  # inserted_at) land on the unit — the thread carrier (ADR-055). The
  # unit's lifecycle state mirrors the pursuit's, matching how the
  # commands keep them folded in production.
  defp build_snapshot(overrides, snapshot_overrides \\ %{}) do
    pursuit_id = Ecto.UUID.generate()
    state = Map.get(overrides, :state, "active")

    pursuit =
      struct(Pursuit, %{
        id: pursuit_id,
        state: state,
        inserted_at: ~U[2026-04-01 00:00:00Z],
        updated_at: ~U[2026-04-01 00:00:00Z]
      })

    unit_attrs =
      Map.merge(
        %{
          id: Ecto.UUID.generate(),
          pursuit_id: pursuit_id,
          state: state,
          attempt_count: 0,
          inserted_at: ~U[2026-04-01 00:00:00Z],
          updated_at: ~U[2026-04-01 00:00:00Z]
        },
        overrides
      )

    base = %Snapshot{
      pursuit: pursuit,
      unit: struct(Unit, unit_attrs),
      current_target: nil,
      queue_state: :unknown,
      now: ~U[2026-04-10 00:00:00Z],
      thresholds: Thresholds.defaults()
    }

    Map.merge(base, snapshot_overrides)
  end

  describe "evaluate/1 — terminal states" do
    test "satisfied returns :no_action" do
      assert Policy.evaluate(build_snapshot(%{state: "satisfied"})) == :no_action
    end

    test "exhausted returns :no_action" do
      assert Policy.evaluate(build_snapshot(%{state: "exhausted"})) == :no_action
    end

    test "cancelled returns :no_action" do
      assert Policy.evaluate(build_snapshot(%{state: "cancelled"})) == :no_action
    end
  end

  describe "evaluate/1 — awaiting decision" do
    test "pursuit with awaiting_decision_at set returns :no_action (waiting on user)" do
      assert Policy.evaluate(
               build_snapshot(%{
                 state: "active",
                 awaiting_decision_at: ~U[2026-04-09 00:00:00Z]
               })
             ) == :no_action
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

    test "honours custom thresholds from the snapshot (Settings-driven override)" do
      thresholds = %Thresholds{
        max_attempts: 2,
        min_age_days: 1,
        stall_window_hours: 24,
        zero_seeders_window_hours: 6
      }

      snapshot =
        build_snapshot(
          %{state: "active", attempt_count: 2, inserted_at: ~U[2026-04-08 00:00:00Z]},
          %{thresholds: thresholds}
        )

      assert Policy.evaluate(snapshot) == {:exhaust, :max_attempts}
    end
  end

  describe "evaluate/1 — terminal download failure" do
    # A client-reported terminal failure (SABnzbd's par2-unrepairable /
    # unpack-failed) is deterministic — no observation window: the same
    # release will fail the same way, so pivot immediately.
    test "download_failed? returns {:auto_cancel, :download_failed} with no window" do
      snapshot = build_snapshot(%{state: "active"}, %{download_failed?: true})

      assert Policy.evaluate(snapshot) == {:auto_cancel, :download_failed}
    end

    test "takes precedence over zero seeders and stall" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{
            download_failed?: true,
            zero_seeders_observed?: true,
            zero_seeders_window_elapsed?: true,
            stall_observed?: true,
            stall_window_elapsed?: true
          }
        )

      assert Policy.evaluate(snapshot) == {:auto_cancel, :download_failed}
    end

    test "a terminal pursuit stays untouched even when its download failed" do
      snapshot = build_snapshot(%{state: "satisfied"}, %{download_failed?: true})

      assert Policy.evaluate(snapshot) == :no_action
    end
  end

  describe "evaluate/1 — zero seeders" do
    test "observed but window not yet elapsed returns :no_action" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{zero_seeders_observed?: true, zero_seeders_window_elapsed?: false}
        )

      assert Policy.evaluate(snapshot) == :no_action
    end

    test "observed AND window elapsed returns {:auto_cancel, :zero_seeders}" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{zero_seeders_observed?: true, zero_seeders_window_elapsed?: true}
        )

      assert Policy.evaluate(snapshot) == {:auto_cancel, :zero_seeders}
    end

    test "not observed → no auto-cancel even if elapsed flag is true" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{zero_seeders_observed?: false, zero_seeders_window_elapsed?: true}
        )

      assert Policy.evaluate(snapshot) == :no_action
    end

    test "zero seeders takes precedence over stall when both are confirmed" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{
            zero_seeders_observed?: true,
            zero_seeders_window_elapsed?: true,
            stall_observed?: true,
            stall_window_elapsed?: true
          }
        )

      assert Policy.evaluate(snapshot) == {:auto_cancel, :zero_seeders}
    end
  end

  describe "evaluate/1 — stall" do
    test "observed but window not yet elapsed returns :no_action" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{stall_observed?: true, stall_window_elapsed?: false}
        )

      assert Policy.evaluate(snapshot) == :no_action
    end

    test "observed AND window elapsed returns {:request_decision, prompt}" do
      snapshot =
        build_snapshot(
          %{state: "active"},
          %{stall_observed?: true, stall_window_elapsed?: true}
        )

      assert {:request_decision, prompt} = Policy.evaluate(snapshot)
      assert prompt =~ "stalled"
      assert prompt =~ "24+"
    end

    test "stall does not fire while the pursuit is already awaiting a decision" do
      snapshot =
        build_snapshot(
          %{state: "active", awaiting_decision_at: ~U[2026-04-09 00:00:00Z]},
          %{stall_observed?: true, stall_window_elapsed?: true}
        )

      assert Policy.evaluate(snapshot) == :no_action
    end

    test "prompt reflects the threshold value carried on the snapshot" do
      thresholds = %Thresholds{
        max_attempts: 4,
        min_age_days: 6,
        stall_window_hours: 12,
        zero_seeders_window_hours: 6
      }

      snapshot =
        build_snapshot(
          %{state: "active"},
          %{
            thresholds: thresholds,
            stall_observed?: true,
            stall_window_elapsed?: true
          }
        )

      assert {:request_decision, prompt} = Policy.evaluate(snapshot)
      assert prompt =~ "12+"
    end
  end

  describe "purity" do
    test "evaluate/1 produces the same output for the same input" do
      snapshot = build_snapshot(%{attempt_count: 4, inserted_at: ~U[2026-04-01 00:00:00Z]})
      assert Policy.evaluate(snapshot) == Policy.evaluate(snapshot)
    end
  end
end
