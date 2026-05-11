defmodule MediaCentarrWeb.AcquisitionLive.ActivityLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Target
  alias MediaCentarrWeb.AcquisitionLive.ActivityLogic, as: Logic

  defp target(overrides \\ %{}) do
    base = %Target{title: "Title", status: "seeking", origin: "auto"}
    Map.merge(base, overrides)
  end

  describe "filter_by_search/2" do
    test "empty search returns all targets unchanged" do
      targets = [target(%{title: "Sample Movie"}), target(%{title: "Other Title"})]
      assert Logic.filter_by_search(targets, "") == targets
    end

    test "case-insensitive substring match" do
      targets = [
        target(%{title: "Sample Movie"}),
        target(%{title: "Other Title"}),
        target(%{title: "sampler"})
      ]

      result = Logic.filter_by_search(targets, "SAMP")
      assert Enum.map(result, & &1.title) == ["Sample Movie", "sampler"]
    end
  end

  describe "status_label/1" do
    test "acquired includes quality" do
      assert Logic.status_label(target(%{status: "acquired", quality: "4K"})) == "Acquired 4K"
    end

    test "cancelled includes reason" do
      assert Logic.status_label(target(%{status: "cancelled", cancelled_reason: "user_disabled"})) ==
               "Cancelled (user_disabled)"
    end

    test "other statuses use raw label" do
      assert Logic.status_label(target(%{status: "seeking"})) == "seeking"
    end
  end

  describe "status_variant/1" do
    test "maps statuses to `<.badge>` variants" do
      assert Logic.status_variant("seeking") == "info"
      assert Logic.status_variant("acquired") == "success"
      assert Logic.status_variant("succeeded") == "success"
      assert Logic.status_variant("failed") == "error"
      assert Logic.status_variant("cancelled") == "ghost"
    end

    test "unknown status falls through to ghost" do
      assert Logic.status_variant("future_status") == "ghost"
    end
  end

  describe "origin_label/1" do
    test "auto origin returns 'auto'" do
      assert Logic.origin_label(target(%{origin: "auto"})) == "auto"
    end

    test "manual origin returns 'manual'" do
      assert Logic.origin_label(target(%{origin: "manual"})) == "manual"
    end

    test "missing/unknown origin defaults to 'auto' (back-compat for legacy rows)" do
      assert Logic.origin_label(target(%{origin: nil})) == "auto"
    end
  end

  describe "origin_variant/1" do
    test "manual gets soft_primary emphasis" do
      assert Logic.origin_variant(target(%{origin: "manual"})) == "soft_primary"
    end

    test "auto gets the neutral type variant (outline, no color)" do
      assert Logic.origin_variant(target(%{origin: "auto"})) == "type"
    end
  end

  describe "last_attempt_summary/1" do
    test "renders 'never' when no attempt logged" do
      assert Logic.last_attempt_summary(target()) == "never"
    end

    test "renders outcome + relative time" do
      at = DateTime.add(DateTime.utc_now(), -90, :second)

      assert Logic.last_attempt_summary(
               target(%{last_attempt_at: at, last_attempt_outcome: "no_results"})
             ) ==
               "no_results • 1m ago"
    end
  end
end
