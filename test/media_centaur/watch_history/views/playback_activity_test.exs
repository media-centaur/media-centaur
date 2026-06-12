defmodule MediaCentaur.WatchHistory.Views.PlaybackActivityTest do
  use MediaCentaur.DataCase, async: true

  alias MediaCentaur.WatchHistory
  alias MediaCentaur.WatchHistory.Views.PlaybackActivity

  describe "empty/0" do
    test "returns a zeroed snapshot for the disconnected mount" do
      assert PlaybackActivity.empty() == %{
               recent: [],
               last_write_at: nil,
               lifetime: %{hours: 0, titles: 0, streak: 0}
             }
    end
  end

  describe "snapshot/0" do
    test "with no history mirrors empty/0" do
      assert PlaybackActivity.snapshot() == PlaybackActivity.empty()
    end

    test "shapes recent events, last_write_at, and lifetime totals" do
      # Anchor fixtures to today so the streak assertion is deterministic
      # regardless of the calendar date the suite runs on: yesterday + today
      # is always a 2-day streak.
      today = Date.utc_today()
      yesterday_dt = DateTime.new!(Date.add(today, -1), ~T[10:00:00.000000], "Etc/UTC")
      today_dt = DateTime.new!(today, ~T[12:00:00.000000], "Etc/UTC")

      {:ok, older} =
        WatchHistory.create_event(%{
          entity_type: :movie,
          title: "Movie A",
          duration_seconds: 3600.0,
          completed_at: yesterday_dt
        })

      {:ok, newer} =
        WatchHistory.create_event(%{
          entity_type: :episode,
          title: "Sample Show — Pilot",
          duration_seconds: 1800.0,
          completed_at: today_dt
        })

      snap = PlaybackActivity.snapshot()

      assert snap.last_write_at == newer.completed_at
      assert [%{title: "Sample Show — Pilot", kind: :episode, at: _}, %{title: "Movie A"}] = snap.recent
      assert snap.lifetime == %{hours: 2, titles: 2, streak: 2}
      _ = older
    end

    test "enriches entries with poster_url from the linked entity" do
      movie = create_movie(%{name: "Movie A"})

      create_image(%{
        owner_type: :movie,
        owner_id: movie.id,
        role: "poster",
        content_url: "posters/movie-a.jpg"
      })

      {:ok, _event} =
        WatchHistory.create_event(%{
          entity_type: :movie,
          movie_id: movie.id,
          title: "Movie A",
          duration_seconds: 3600.0,
          completed_at: DateTime.utc_now()
        })

      assert [%{poster_url: "/media-images/posters/movie-a.jpg"}] = PlaybackActivity.snapshot().recent
    end

    test "entries for deleted or posterless entities carry a nil poster_url" do
      {:ok, _event} =
        WatchHistory.create_event(%{
          entity_type: :movie,
          title: "Orphaned Movie",
          duration_seconds: 3600.0,
          completed_at: DateTime.utc_now()
        })

      assert [%{poster_url: nil}] = PlaybackActivity.snapshot().recent
    end

    test "entries carry two-tier title parts" do
      {:ok, _event} =
        WatchHistory.create_event(%{
          entity_type: :episode,
          title: "Sample Show S01E03 — The One With the Plan",
          duration_seconds: 1800.0,
          completed_at: DateTime.utc_now()
        })

      assert [%{primary: "Sample Show", secondary: "S01E03 — The One With the Plan"}] =
               PlaybackActivity.snapshot().recent
    end
  end

  describe "title_parts/2" do
    test "splits a full episode title into series and episode line" do
      assert PlaybackActivity.title_parts(:episode, "Sample Show S01E03 — The One With the Plan") ==
               {"Sample Show", "S01E03 — The One With the Plan"}
    end

    test "splits a nameless episode title into series and code" do
      assert PlaybackActivity.title_parts(:episode, "Sample Show S01E03") ==
               {"Sample Show", "S01E03"}
    end

    test "falls back to a type label when an episode title doesn't match the recorded format" do
      assert PlaybackActivity.title_parts(:episode, "Free-form recording") ==
               {"Free-form recording", "Episode"}
    end

    test "movies and videos use their name with a type label" do
      assert PlaybackActivity.title_parts(:movie, "Movie A") == {"Movie A", "Movie"}
      assert PlaybackActivity.title_parts(:video_object, "Sample Clip") == {"Sample Clip", "Video"}
    end
  end
end
