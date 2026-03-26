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
end
