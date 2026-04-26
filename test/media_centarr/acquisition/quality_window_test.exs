defmodule MediaCentarr.Acquisition.QualityWindowTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.{Grab, QualityWindow}

  defp grab(overrides) do
    base = %Grab{
      min_quality: "hd_1080p",
      max_quality: "uhd_4k",
      quality_4k_patience_hours: 48,
      inserted_at: ~U[2026-01-01 00:00:00Z]
    }

    Map.merge(base, overrides)
  end

  describe "min_at/2 — within patience window with 4K max" do
    test "1 hour after enqueue, effective_min is 4K (insist on 4K)" do
      now = ~U[2026-01-01 01:00:00Z]
      assert QualityWindow.min_at(grab(%{}), now) == "uhd_4k"
    end

    test "47 hours after enqueue (just inside 48h window), still 4K" do
      now = ~U[2026-01-02 23:00:00Z]
      assert QualityWindow.min_at(grab(%{}), now) == "uhd_4k"
    end
  end

  describe "min_at/2 — outside patience window" do
    test "exactly at the patience boundary (48h), relaxes to floor" do
      now = ~U[2026-01-03 00:00:00Z]
      assert QualityWindow.min_at(grab(%{}), now) == "hd_1080p"
    end

    test "well past patience, relaxes to floor" do
      now = ~U[2026-01-10 00:00:00Z]
      assert QualityWindow.min_at(grab(%{}), now) == "hd_1080p"
    end
  end

  describe "min_at/2 — patience irrelevant when max_quality is not 4K" do
    test "1080p-only grab returns 1080p floor immediately, even within window" do
      now = ~U[2026-01-01 01:00:00Z]
      assert QualityWindow.min_at(grab(%{max_quality: "hd_1080p"}), now) == "hd_1080p"
    end
  end

  describe "min_at/2 — patience disabled (0 hours)" do
    test "returns floor immediately, even with 4K max" do
      now = ~U[2026-01-01 01:00:00Z]
      assert QualityWindow.min_at(grab(%{quality_4k_patience_hours: 0}), now) == "hd_1080p"
    end
  end

  describe "min_at/2 — bounds normalisation" do
    test "treats min == max == 4K as 4K-only, no fallback ever" do
      now = ~U[2026-01-10 00:00:00Z]
      g = grab(%{min_quality: "uhd_4k", max_quality: "uhd_4k", quality_4k_patience_hours: 0})
      assert QualityWindow.min_at(g, now) == "uhd_4k"
    end
  end
end
