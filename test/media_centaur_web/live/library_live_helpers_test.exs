defmodule MediaCentaurWeb.LibraryLiveHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentaurWeb.LibraryLive
  alias MediaCentaur.TestFactory

  # --- event_poster_url/1 ---

  describe "event_poster_url/1" do
    test "returns nil when all FK fields are nil (no entity loaded)" do
      event = TestFactory.build_watch_event(%{movie: nil, episode: nil, video_object: nil})
      assert LibraryLive.event_poster_url(event) == nil
    end

    test "returns nil when movie has no poster image" do
      movie = TestFactory.build_movie(%{images: []})
      event = TestFactory.build_watch_event(%{movie: movie})
      assert LibraryLive.event_poster_url(event) == nil
    end

    test "returns the image URL when movie has a poster image with a content_url" do
      image = TestFactory.build_image(%{role: "poster", content_url: "movies/abc/poster.jpg"})
      movie = TestFactory.build_movie(%{images: [image]})
      event = TestFactory.build_watch_event(%{movie: movie})
      assert LibraryLive.event_poster_url(event) == "/media-images/movies/abc/poster.jpg"
    end
  end

  # --- history_time_ago/1 ---

  describe "history_time_ago/1" do
    test "returns 'Today' for a datetime from today" do
      now = DateTime.utc_now()
      assert LibraryLive.history_time_ago(now) == "Today"
    end

    test "returns 'Yesterday' for a datetime from 1 day ago" do
      yesterday = DateTime.add(DateTime.utc_now(), -1, :day)
      assert LibraryLive.history_time_ago(yesterday) == "Yesterday"
    end

    test "returns 'X days ago' for datetimes within the same week" do
      three_days_ago = DateTime.add(DateTime.utc_now(), -3, :day)
      assert LibraryLive.history_time_ago(three_days_ago) == "3 days ago"
    end

    test "returns '2 weeks ago' for 15 days ago" do
      fifteen_days_ago = DateTime.add(DateTime.utc_now(), -15, :day)
      assert LibraryLive.history_time_ago(fifteen_days_ago) == "2 weeks ago"
    end

    test "returns '1 month ago' for 40 days ago" do
      forty_days_ago = DateTime.add(DateTime.utc_now(), -40, :day)
      assert LibraryLive.history_time_ago(forty_days_ago) == "1 month ago"
    end

    test "returns 'X months ago' for older datetimes" do
      ninety_days_ago = DateTime.add(DateTime.utc_now(), -90, :day)
      assert LibraryLive.history_time_ago(ninety_days_ago) == "3 months ago"
    end

    test "returns '1 week ago' for 7 days ago" do
      seven_days_ago = DateTime.add(DateTime.utc_now(), -7, :day)
      assert LibraryLive.history_time_ago(seven_days_ago) == "1 week ago"
    end
  end
end
