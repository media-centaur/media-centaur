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
  end
end
