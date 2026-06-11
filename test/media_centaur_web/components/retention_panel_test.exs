defmodule MediaCentaurWeb.RetentionPanelTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Retention.PolicyStatus
  alias MediaCentaurWeb.RetentionPanel

  defp policy_status(overrides) do
    struct!(
      %PolicyStatus{
        key: :sample_policy,
        subsystem: :system,
        label: "Sample policy",
        description: "Sample rows older than 30 days are deleted.",
        mode: :sweep
      },
      overrides
    )
  end

  describe "sweep_summary/1" do
    test "a swept policy reads sweep time, last-run count, and lifetime total" do
      status =
        policy_status(%{
          mode: :sweep,
          last_ran_at: DateTime.add(DateTime.utc_now(), -3 * 3600, :second),
          pruned_last_run: 12,
          pruned_total: 480
        })

      assert RetentionPanel.sweep_summary(status) == "swept 3h ago · 12 removed (480 all-time)"
    end

    test "a sweep policy that has not run yet says so" do
      assert RetentionPanel.sweep_summary(policy_status(%{mode: :sweep, last_ran_at: nil})) ==
               "not swept yet"
    end

    test "an external policy with recorded runs reads pruned time and counts" do
      status =
        policy_status(%{
          mode: :external,
          last_ran_at: DateTime.add(DateTime.utc_now(), -5 * 60, :second),
          pruned_last_run: 2,
          pruned_total: 96
        })

      assert RetentionPanel.sweep_summary(status) == "pruned 5m ago · 2 removed (96 all-time)"
    end

    test "an external policy with no recorded runs reads continuous" do
      assert RetentionPanel.sweep_summary(policy_status(%{mode: :external, last_ran_at: nil})) ==
               "continuous"
    end

    test "a forever policy reads kept forever" do
      assert RetentionPanel.sweep_summary(policy_status(%{mode: :forever})) == "kept forever"
    end
  end
end
