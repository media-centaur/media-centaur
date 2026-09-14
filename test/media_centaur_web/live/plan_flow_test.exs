defmodule MediaCentaurWeb.Live.PlanFlowTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Live.PlanFlow

  describe "download_flash/1" do
    test "names what is being looked for" do
      assert PlanFlow.download_flash("Sample Show S1E2") ==
               "Finding a release for Sample Show S1E2"
    end
  end

  describe "failure_flash/2" do
    test "nothing to plan is a fact about the library" do
      assert PlanFlow.failure_flash("Sample Show", :nothing_to_plan) =~ "already in your library"
    end

    test "the unit reasons ignore the label" do
      assert PlanFlow.failure_flash("Sample Show", :unaired) == "That episode hasn't aired yet."

      assert PlanFlow.failure_flash("Sample Show", :already_here) ==
               "That episode is already in your library."

      assert PlanFlow.failure_flash("Sample Show", :not_listed) ==
               "TMDB doesn't list that episode for this season."

      assert PlanFlow.failure_flash("Sample Show", :tracked) ==
               "That episode is already on its way."
    end

    test "anything else points at TMDB and names the title" do
      assert PlanFlow.failure_flash("Sample Show", :timeout) ==
               "Couldn't plan Sample Show. Check TMDB under Settings and try again."
    end
  end
end
