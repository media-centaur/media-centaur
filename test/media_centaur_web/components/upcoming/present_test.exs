defmodule MediaCentaurWeb.Components.Upcoming.PresentTest do
  @moduledoc "Pure presentation helpers for the Upcoming rail — labels, tones, descriptors, relative dates."
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.UpcomingFeed.Event
  alias MediaCentaurWeb.Components.Upcoming.Present

  @today ~D[2026-06-14]

  describe "status_label/1 and status_tone/1" do
    test "each status has a label and a tone" do
      for status <- [:armed, :under_pursuit, :in_library, :theatrical_info, :upcoming, :unscheduled] do
        assert is_binary(Present.status_label(status))
        assert Present.status_tone(status) in [:success, :info, :muted, :neutral]
      end
    end

    test "armed reads as auto-grabbing (success); under_pursuit as downloading (info); theatrical as muted info-only" do
      assert Present.status_label(:armed) =~ "grab"
      assert Present.status_tone(:armed) == :success
      assert Present.status_label(:under_pursuit) =~ "Download"
      assert Present.status_tone(:under_pursuit) == :info
      assert Present.status_tone(:theatrical_info) == :muted
    end
  end

  describe "what_drops/1" do
    test "an episode reads SxxExx" do
      event = %Event{kind: :episode, season_number: 1, episode_number: 4, media_type: :tv_series}
      assert Present.what_drops(event) == "S01E04"
    end

    test "a season drop names the season and episode count" do
      event = %Event{kind: :season_drop, season_number: 2, episode_count: 8, media_type: :tv_series}
      descriptor = Present.what_drops(event)
      assert descriptor =~ "Season 2"
      assert descriptor =~ "8"
    end

    test "a movie reads by release type" do
      assert Present.what_drops(%Event{kind: :movie, release_type: "digital"}) =~ "Digital"
      assert Present.what_drops(%Event{kind: :movie, release_type: "physical"}) =~ "Physical"
      assert Present.what_drops(%Event{kind: :movie, release_type: "theatrical"}) =~ "theaters"
    end
  end

  describe "relative_day/2" do
    test "today, tomorrow, near days, and far dates" do
      assert Present.relative_day(@today, @today) == "Today"
      assert Present.relative_day(Date.add(@today, 1), @today) == "Tomorrow"
      assert Present.relative_day(Date.add(@today, 3), @today) =~ "3 days"
      assert Present.relative_day(Date.add(@today, 40), @today) =~ "Jul"
    end

    test "a date already passed (linger window) reads as Today" do
      assert Present.relative_day(Date.add(@today, -1), @today) == "Today"
    end
  end

  describe "auto_grab_summary/3" do
    test "no acquisition → off, honest label" do
      summary = Present.auto_grab_summary("all_releases", "all_releases", false)
      refute summary.on?
      assert summary.label =~ "configured"
    end

    test "full-auto → on" do
      summary = Present.auto_grab_summary("all_releases", "off", true)
      assert summary.on?
      assert summary.label =~ "every release"
    end

    test "global inherits the default" do
      assert Present.auto_grab_summary("global", "all_releases", true).on?
      refute Present.auto_grab_summary("global", "off", true).on?
    end

    test "ask and off are not on" do
      refute Present.auto_grab_summary("ask", "all_releases", true).on?
      assert Present.auto_grab_summary("ask", "all_releases", true).label =~ "Ask"
      refute Present.auto_grab_summary("off", "all_releases", true).on?
      assert Present.auto_grab_summary("off", "all_releases", true).label =~ "Not"
    end
  end

  describe "bucket_label/1" do
    test "labels every bucket" do
      assert Present.bucket_label(:today) == "Today"
      assert Present.bucket_label(:this_week) == "This week"
      assert Present.bucket_label(:next_week) == "Next week"
      assert Present.bucket_label(:later) =~ "Later"
      assert Present.bucket_label(:beyond) == "Beyond"
    end
  end
end
