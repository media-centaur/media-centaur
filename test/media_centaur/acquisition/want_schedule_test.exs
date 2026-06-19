defmodule MediaCentaur.Acquisition.WantScheduleTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Acquisition.WantSchedule

  @hour 3600
  @day 24 * @hour

  defp at(now, offset_seconds), do: DateTime.add(now, offset_seconds, :second)

  describe "interval_seconds/1" do
    test "0–48h hot window re-searches every 30 minutes" do
      assert WantSchedule.interval_seconds(0) == 30 * 60
      assert WantSchedule.interval_seconds(47 * @hour) == 30 * 60
    end

    test "48h–7d backs off to 4 hours" do
      assert WantSchedule.interval_seconds(48 * @hour) == 4 * @hour
      assert WantSchedule.interval_seconds(6 * @day) == 4 * @hour
    end

    test "7–30d backs off to daily" do
      assert WantSchedule.interval_seconds(7 * @day) == @day
      assert WantSchedule.interval_seconds(29 * @day) == @day
    end

    test "30d+ settles at weekly, forever" do
      assert WantSchedule.interval_seconds(30 * @day) == 7 * @day
      assert WantSchedule.interval_seconds(365 * @day) == 7 * @day
    end
  end

  describe "floor_elevated?/3" do
    test "patience 0 never elevates" do
      now = DateTime.utc_now()
      want = %{wanted_since: at(now, -@hour), last_searched_at: nil}
      refute WantSchedule.floor_elevated?(want, 0, now)
    end

    test "elevated while inside the patience window" do
      now = DateTime.utc_now()
      want = %{wanted_since: at(now, -1 * @hour), last_searched_at: nil}
      assert WantSchedule.floor_elevated?(want, 24, now)
    end

    test "not elevated once the window has lapsed" do
      now = DateTime.utc_now()
      want = %{wanted_since: at(now, -48 * @hour), last_searched_at: nil}
      refute WantSchedule.floor_elevated?(want, 24, now)
    end
  end

  describe "due?/3" do
    test "a never-searched want is due immediately" do
      now = DateTime.utc_now()
      want = %{wanted_since: at(now, -@hour), last_searched_at: nil}
      assert WantSchedule.due?(want, 0, now)
    end

    test "not due when the band interval has not elapsed since the last search" do
      now = DateTime.utc_now()
      # Fresh want (30-minute band); searched 10 minutes ago.
      want = %{wanted_since: at(now, -@hour), last_searched_at: at(now, -10 * 60)}
      refute WantSchedule.due?(want, 0, now)
    end

    test "due once the band interval has elapsed" do
      now = DateTime.utc_now()
      # Fresh want (30-minute band); searched 31 minutes ago.
      want = %{wanted_since: at(now, -@hour), last_searched_at: at(now, -31 * 60)}
      assert WantSchedule.due?(want, 0, now)
    end

    test "patience expiry forces due even when the band interval has not elapsed" do
      now = DateTime.utc_now()
      # 50h-old want → 4h band. Searched 3h ago (band not elapsed), but the
      # 48h patience window lapsed 2h ago, so the floor dropped and the want's
      # negative "unfound at 4K" knowledge is stale — re-search immediately.
      want = %{wanted_since: at(now, -50 * @hour), last_searched_at: at(now, -3 * @hour)}
      assert WantSchedule.due?(want, 48, now)
    end

    test "still waits the band when the patience window has not yet lapsed" do
      now = DateTime.utc_now()
      # Same 50h want and 3h-ago search, but patience is long enough that the
      # window is still open — no override, so the 4h band still applies.
      want = %{wanted_since: at(now, -50 * @hour), last_searched_at: at(now, -3 * @hour)}
      refute WantSchedule.due?(want, 100, now)
    end
  end
end
