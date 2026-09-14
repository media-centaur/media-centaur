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
    test "Track says what Coming up shows, or that auto-grab holds it on" do
      assert TrackingControls.track_description(:movie, :list) =~ "Theatrical, digital and disc dates"
      assert TrackingControls.track_description(:tv_series, :follow) =~ "Upcoming episodes"
      assert TrackingControls.track_description(:movie, :grab) == "Stays on while auto-grab is on."
    end

    test "Auto-grab follows the approval policy and the media type, and says where that is set" do
      assert TrackingControls.grab_description(:movie, "review") =~
               "a plan waits for your approval on Incoming"

      assert TrackingControls.grab_description(:movie, "automatic") =~
               "downloads when it drops, without asking"

      assert TrackingControls.grab_description(:tv_series, "review") =~
               "New and missing episodes are planned"

      assert TrackingControls.grab_description(:tv_series, "automatic") =~
               "New and missing episodes download without asking"

      for media_type <- [:movie, :tv_series], policy <- ["review", "automatic"] do
        assert TrackingControls.grab_description(media_type, policy) =~
                 "Settings → Acquisition → Download button"
      end
    end
  end
end
