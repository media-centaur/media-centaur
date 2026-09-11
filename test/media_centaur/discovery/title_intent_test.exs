defmodule MediaCentaur.Discovery.TitleIntentTest do
  @moduledoc """
  The rung ladder is the whole of a person's standing intent about a
  title. Off is the absence of a record, so it is never a stored value —
  which is what makes "Off deletes" a fact about the schema rather than a
  rule something has to enforce.
  """
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Discovery.TitleIntent

  describe "the ladder" do
    test "runs from Ignored to Default, and Off is not on it" do
      assert TitleIntent.rungs() == [:ignored, :list, :follow, :ask, :grab, :default]
      refute :off in TitleIntent.rungs()
    end

    test "rung_at_least?/2 orders the ladder" do
      assert TitleIntent.rung_at_least?(:follow, :follow)
      assert TitleIntent.rung_at_least?(:grab, :follow)
      assert TitleIntent.rung_at_least?(:default, :follow)
      refute TitleIntent.rung_at_least?(:list, :follow)
    end

    test "Ignored is a record below List — an opinion, unlike Off, but not on the list" do
      refute TitleIntent.rung_at_least?(:ignored, :list)
      assert TitleIntent.rung_at_least?(:ignored, :ignored)
      assert TitleIntent.rung_at_least?(:list, :ignored)
      refute TitleIntent.follows_releases?(:ignored)
    end

    test "a title with no record is below every rung" do
      assert TitleIntent.rung_at_least?(nil, :list) == false
      assert TitleIntent.rung_at_least?(nil, :follow) == false
    end

    test "following starts at Follow — List is on the list and nothing more" do
      refute TitleIntent.follows_releases?(:list)
      assert TitleIntent.follows_releases?(:follow)
      assert TitleIntent.follows_releases?(:ask)
      assert TitleIntent.follows_releases?(:grab)
      assert TitleIntent.follows_releases?(:default)
      refute TitleIntent.follows_releases?(nil)
    end
  end

  describe "grab_mode/2" do
    test "only Ask and Grab commit; Default defers to the global setting, live" do
      assert TitleIntent.grab_mode(:grab, "off") == "all_releases"
      assert TitleIntent.grab_mode(:ask, "off") == "ask"
      assert TitleIntent.grab_mode(:default, "all_releases") == "all_releases"
      assert TitleIntent.grab_mode(:default, "off") == "off"
    end

    test "the rungs below Ask never grab, whatever the global setting says" do
      for rung <- [nil, :ignored, :list, :follow] do
        assert TitleIntent.grab_mode(rung, "all_releases") == "off",
               "#{inspect(rung)} must never grab"
      end
    end
  end

  describe "friend_provenance/2" do
    test "names the activity a friend-sourced record came from, with its note" do
      assert TitleIntent.friend_provenance("activity-1", "Watch it.") ==
               %{source: :friend, activity_id: "activity-1", note: "Watch it."}

      assert TitleIntent.friend_provenance("activity-1", nil) ==
               %{source: :friend, activity_id: "activity-1", note: nil}
    end
  end
end
