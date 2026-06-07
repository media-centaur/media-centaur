defmodule MediaCentaur.SelfUpdate.HealthTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.SelfUpdate.Health

  describe "check failure streak" do
    test "starts at zero with a nil apply failure when nothing is persisted" do
      assert %{check_failure_streak: 0, last_apply_failure: nil} = Health.snapshot()
    end

    test "record_check_failure/0 increments the streak" do
      :ok = Health.record_check_failure()
      :ok = Health.record_check_failure()

      assert %{check_failure_streak: 2} = Health.snapshot()
    end

    test "record_check_success/0 resets the streak to zero" do
      :ok = Health.record_check_failure()
      :ok = Health.record_check_failure()
      :ok = Health.record_check_success()

      assert %{check_failure_streak: 0} = Health.snapshot()
    end
  end

  describe "last apply outcome" do
    test "record_apply_failed/1 records the failure with its reason" do
      :ok = Health.record_apply_failed(:checksum_mismatch)

      assert %{last_apply_failure: %{reason: reason, at: %DateTime{}}} = Health.snapshot()
      assert reason =~ "checksum_mismatch"
    end

    test "clear_apply_failure/0 clears a recorded failure" do
      :ok = Health.record_apply_failed(:checksum_mismatch)
      :ok = Health.clear_apply_failure()

      assert %{last_apply_failure: nil} = Health.snapshot()
    end

    test "a later failure supersedes an earlier cleared one" do
      :ok = Health.record_apply_failed(:checksum_mismatch)
      :ok = Health.clear_apply_failure()
      :ok = Health.record_apply_failed({:task_crashed, :boom})

      assert %{last_apply_failure: %{reason: reason}} = Health.snapshot()
      assert reason =~ "task_crashed"
    end
  end
end
