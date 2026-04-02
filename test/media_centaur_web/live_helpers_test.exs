defmodule MediaCentaurWeb.LiveHelpersTest do
  use ExUnit.Case, async: true

  import MediaCentaurWeb.LiveHelpers

  describe "format_iso_duration/1" do
    test "formats hours and minutes" do
      assert format_iso_duration("PT3H48M") == "3h 48m"
      assert format_iso_duration("PT1H30M") == "1h 30m"
    end

    test "formats hours with zero minutes" do
      assert format_iso_duration("PT2H0M") == "2h 0m"
    end

    test "omits hours when zero" do
      assert format_iso_duration("PT0H45M") == "45m"
      assert format_iso_duration("PT45M") == "45m"
    end

    test "returns nil for nil" do
      assert format_iso_duration(nil) == nil
    end
  end

  describe "image_url/2" do
    test "returns local path for content_url" do
      entity = %{images: [%{role: "poster", content_url: "abc/poster.jpg"}]}
      assert image_url(entity, "poster") == "/media-images/abc/poster.jpg"
    end

    test "returns nil when no content_url" do
      entity = %{images: [%{role: "backdrop", content_url: nil}]}

      assert image_url(entity, "backdrop") == nil
    end

    test "returns nil when no image for role" do
      entity = %{images: [%{role: "poster", content_url: "x.jpg"}]}
      assert image_url(entity, "backdrop") == nil
    end

    test "returns nil when images is nil" do
      entity = %{images: nil}
      assert image_url(entity, "poster") == nil
    end
  end

  describe "time_ago/1" do
    test "returns empty string for nil" do
      assert time_ago(nil) == ""
    end

    test "returns just now for recent timestamps" do
      now = DateTime.utc_now()
      assert time_ago(now) == "just now"
    end

    test "returns minutes ago" do
      minutes_ago = DateTime.add(DateTime.utc_now(), -180, :second)
      assert time_ago(minutes_ago) == "3m ago"
    end

    test "returns hours ago" do
      hours_ago = DateTime.add(DateTime.utc_now(), -7200, :second)
      assert time_ago(hours_ago) == "2h ago"
    end

    test "returns days ago" do
      days_ago = DateTime.add(DateTime.utc_now(), -3 * 86_400, :second)
      assert time_ago(days_ago) == "3d ago"
    end

    test "returns formatted date for old timestamps" do
      old = DateTime.new!(~D[2025-01-15], ~T[12:00:00], "Etc/UTC")
      assert time_ago(old) == "Jan 15"
    end

    test "handles NaiveDateTime by converting to UTC" do
      naive = NaiveDateTime.utc_now()
      assert time_ago(naive) == "just now"
    end
  end
end
