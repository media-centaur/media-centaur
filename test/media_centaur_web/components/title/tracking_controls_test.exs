defmodule MediaCentaurWeb.Components.Title.TrackingControlsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaurWeb.Components.Title.TrackingControls

  describe "control_form/1 — which form the block takes (UIDR-039)" do
    test "no record: nothing — listing is the bookmark's act" do
      assert TrackingControls.control_form(nil) == :none
    end

    test "ignored: the one line" do
      assert TrackingControls.control_form(:ignored) == :ignored
    end

    test "listed: the rows" do
      for rung <- [:list, :follow, :grab], do: assert(TrackingControls.control_form(rung) == :controls)
    end
  end

  describe "rows/1 — which rows a listed title gets" do
    test "a movie the library owns is complete: no rows" do
      assert TrackingControls.rows(%{media_type: :movie, release_ahead?: true, complete?: true}) == []
    end

    test "a movie that is out offers only Auto-grab — nothing left to track" do
      assert TrackingControls.rows(%{media_type: :movie, release_ahead?: false, complete?: false}) ==
               [:grab]
    end

    test "a movie with a release ahead, and any series, offer both" do
      assert TrackingControls.rows(%{media_type: :movie, release_ahead?: true, complete?: false}) ==
               [:track, :grab]

      assert TrackingControls.rows(%{media_type: :tv_series, release_ahead?: true, complete?: false}) ==
               [:track, :grab]
    end
  end

  describe "the rung each row sets" do
    test "Track: Follow when off, List when on, nothing while auto-grab holds it on" do
      assert TrackingControls.track_choice(:list) == "follow"
      assert TrackingControls.track_choice(:follow) == "list"
      assert TrackingControls.track_choice(:grab) == nil
    end

    test "Auto-grab: Grab when off; when on, back to Follow, or to List when there is no Track row" do
      assert TrackingControls.grab_choice(:list, [:track, :grab]) == "grab"
      assert TrackingControls.grab_choice(:follow, [:track, :grab]) == "grab"
      assert TrackingControls.grab_choice(:grab, [:track, :grab]) == "follow"
      assert TrackingControls.grab_choice(:grab, [:grab]) == "list"
    end
  end

  describe "the rows' lines" do
    test "Notify says which dates Coming up will carry, or that auto-grab holds it on" do
      assert TrackingControls.track_description(:movie, :list) =~ "theatrical, digital and disc dates"
      assert TrackingControls.track_description(:tv_series, :follow) =~ "new episodes"
      assert TrackingControls.track_description(:movie, :grab) == "Stays on while auto-grab is on."
    end

    test "Auto-grab follows the approval policy and the media type, in one short line" do
      assert TrackingControls.grab_description(:movie, "automatic") == "Downloads when it drops."

      assert TrackingControls.grab_description(:movie, "review") ==
               "Plans when it drops and waits for your approval."

      assert TrackingControls.grab_description(:tv_series, "automatic") ==
               "Downloads episodes as they air."

      assert TrackingControls.grab_description(:tv_series, "review") ==
               "Plans episodes as they air and waits for your approval."
    end
  end
end
