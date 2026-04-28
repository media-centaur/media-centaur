defmodule MediaCentarrWeb.AcquisitionLive.ActivityLogicTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.Grab
  alias MediaCentarrWeb.AcquisitionLive.ActivityLogic, as: Logic

  defp grab(overrides \\ %{}) do
    base = %Grab{title: "Title", status: "searching", origin: "auto"}
    Map.merge(base, overrides)
  end

  describe "filter_by_search/2" do
    test "empty search returns all grabs unchanged" do
      grabs = [grab(%{title: "Sample Movie"}), grab(%{title: "Other Title"})]
      assert Logic.filter_by_search(grabs, "") == grabs
    end

    test "case-insensitive substring match" do
      grabs = [
        grab(%{title: "Sample Movie"}),
        grab(%{title: "Other Title"}),
        grab(%{title: "sampler"})
      ]

      result = Logic.filter_by_search(grabs, "SAMP")
      assert Enum.map(result, & &1.title) == ["Sample Movie", "sampler"]
    end
  end

  describe "episode_label/1" do
    test "movie (no season/episode) renders as dash" do
      assert Logic.episode_label(grab()) == "—"
    end

    test "season pack (no episode) renders 'Season N'" do
      assert Logic.episode_label(grab(%{season_number: 3})) == "Season 3"
    end

    test "episode pads single digits" do
      assert Logic.episode_label(grab(%{season_number: 1, episode_number: 4})) == "S01E04"
    end

    test "double-digit episodes are not padded further" do
      assert Logic.episode_label(grab(%{season_number: 12, episode_number: 23})) == "S12E23"
    end
  end

  describe "status_label/1" do
    test "grabbed includes quality" do
      assert Logic.status_label(grab(%{status: "grabbed", quality: "4K"})) == "Grabbed 4K"
    end

    test "cancelled includes reason" do
      assert Logic.status_label(grab(%{status: "cancelled", cancelled_reason: "user_disabled"})) ==
               "Cancelled (user_disabled)"
    end

    test "other statuses use raw label" do
      assert Logic.status_label(grab(%{status: "snoozed"})) == "snoozed"
    end
  end

  describe "status_class/1" do
    test "maps statuses to DaisyUI badge classes" do
      assert Logic.status_class("searching") == "badge-info"
      assert Logic.status_class("snoozed") == "badge-warning"
      assert Logic.status_class("grabbed") == "badge-success"
      assert Logic.status_class("abandoned") == "badge-error"
      assert Logic.status_class("cancelled") == "badge-ghost"
    end

    test "unknown status falls through to ghost" do
      assert Logic.status_class("future_status") == "badge-ghost"
    end
  end

  describe "origin_label/1" do
    test "auto origin returns 'auto'" do
      assert Logic.origin_label(grab(%{origin: "auto"})) == "auto"
    end

    test "manual origin returns 'manual'" do
      assert Logic.origin_label(grab(%{origin: "manual"})) == "manual"
    end

    test "missing/unknown origin defaults to 'auto' (back-compat for legacy rows)" do
      assert Logic.origin_label(grab(%{origin: nil})) == "auto"
    end
  end

  describe "origin_class/1" do
    test "manual gets a primary outline" do
      assert Logic.origin_class(grab(%{origin: "manual"})) =~ "badge-primary"
    end

    test "auto gets a plain outline" do
      assert Logic.origin_class(grab(%{origin: "auto"})) == "badge-outline"
    end
  end

  describe "last_attempt_summary/1" do
    test "renders 'never' when no attempt logged" do
      assert Logic.last_attempt_summary(grab()) == "never"
    end

    test "renders outcome + relative time" do
      at = DateTime.add(DateTime.utc_now(), -90, :second)

      assert Logic.last_attempt_summary(grab(%{last_attempt_at: at, last_attempt_outcome: "no_results"})) ==
               "no_results • 1m ago"
    end
  end
end
