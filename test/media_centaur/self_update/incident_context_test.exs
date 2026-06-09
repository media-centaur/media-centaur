defmodule MediaCentaur.SelfUpdate.IncidentContextTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.SelfUpdate.IncidentContext

  @now ~U[2026-06-07 12:00:00Z]
  @enabled %{enabled: true, interval_minutes: 15}

  defp snapshot(overrides \\ %{}) do
    Map.merge(%{check_failure_streak: 0, last_apply_failure: nil}, overrides)
  end

  describe "decide/4 — healthy" do
    test "everything clear is :ok" do
      assert IncidentContext.decide(snapshot(), {:ok, @now}, @now, @enabled) == :ok
    end

    test "an update being available is not a fault" do
      # view_status classification is irrelevant here — assess only faults on
      # check/apply failures and stalls, never on \"update available\".
      assert IncidentContext.decide(snapshot(), {:ok, @now}, @now, @enabled) == :ok
    end
  end

  describe "decide/4 — apply failure (error, dominant)" do
    test "a recorded apply failure raises :apply_failed/:error" do
      snap = snapshot(%{last_apply_failure: %{reason: "checksum_mismatch", at: @now}})

      assert {:fault, :apply_failed, :error, _ids} =
               IncidentContext.decide(snap, {:ok, @now}, @now, @enabled)
    end

    test "apply failure dominates a check-failure streak and a stall" do
      old = DateTime.add(@now, -100, :minute)

      snap =
        snapshot(%{
          last_apply_failure: %{reason: "boom", at: @now},
          check_failure_streak: 9
        })

      assert {:fault, :apply_failed, :error, _} =
               IncidentContext.decide(snap, {:ok, old}, @now, @enabled)
    end
  end

  describe "decide/4 — check failing (warning)" do
    test "three consecutive failures raise :check_failing/:warning" do
      snap = snapshot(%{check_failure_streak: 3})

      assert {:fault, :check_failing, :warning, _} =
               IncidentContext.decide(snap, {:ok, @now}, @now, @enabled)
    end

    test "two failures are below the threshold" do
      snap = snapshot(%{check_failure_streak: 2})
      assert IncidentContext.decide(snap, {:ok, @now}, @now, @enabled) == :ok
    end

    test "check failing dominates a stall" do
      old = DateTime.add(@now, -100, :minute)
      snap = snapshot(%{check_failure_streak: 5})

      assert {:fault, :check_failing, :warning, _} =
               IncidentContext.decide(snap, {:ok, old}, @now, @enabled)
    end
  end

  describe "decide/4 — checks stalled (warning)" do
    test "no successful check in >= 3x the interval raises :checks_stalled/:warning" do
      # interval 15min, 3x = 45min; last success 50min ago
      old = DateTime.add(@now, -50, :minute)

      assert {:fault, :checks_stalled, :warning, _} =
               IncidentContext.decide(snapshot(), {:ok, old}, @now, @enabled)
    end

    test "a recent successful check is not stalled" do
      recent = DateTime.add(@now, -10, :minute)
      assert IncidentContext.decide(snapshot(), {:ok, recent}, @now, @enabled) == :ok
    end

    test "never having checked is not a stall" do
      assert IncidentContext.decide(snapshot(), :none, @now, @enabled) == :ok
    end

    test "stall is suppressed when background checks are disabled" do
      old = DateTime.add(@now, -1000, :minute)
      disabled = %{enabled: false, interval_minutes: 15}
      assert IncidentContext.decide(snapshot(), {:ok, old}, @now, disabled) == :ok
    end

    test "stall is suppressed when the app hasn't been up long enough to have checked" do
      # last success 50min ago (> the 45min stall window), but the app has only
      # been up 10min this run — the persisted timestamp is stale because we were
      # down/suspended, not because the scheduler is wedged.
      old = DateTime.add(@now, -50, :minute)
      just_booted = %{enabled: true, interval_minutes: 15, uptime_minutes: 10}

      assert IncidentContext.decide(snapshot(), {:ok, old}, @now, just_booted) == :ok
    end

    test "stall still faults once the app has been up past the stall window" do
      old = DateTime.add(@now, -50, :minute)
      long_up = %{enabled: true, interval_minutes: 15, uptime_minutes: 60}

      assert {:fault, :checks_stalled, :warning, _} =
               IncidentContext.decide(snapshot(), {:ok, old}, @now, long_up)
    end
  end
end
