defmodule MediaCentaur.Acquisition.WantScheduleTest do
  use MediaCentaur.Case, async: true

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

  describe "due?/2" do
    test "a never-searched want is due immediately" do
      now = DateTime.utc_now()
      want = %{wanted_since: at(now, -@hour), last_searched_at: nil}
      assert WantSchedule.due?(want, now)
    end

    test "not due when the band interval has not elapsed since the last search" do
      now = DateTime.utc_now()
      # Fresh want (30-minute band); searched 10 minutes ago.
      want = %{wanted_since: at(now, -@hour), last_searched_at: at(now, -10 * 60)}
      refute WantSchedule.due?(want, now)
    end

    test "due once the band interval has elapsed" do
      now = DateTime.utc_now()
      # Fresh want (30-minute band); searched 31 minutes ago.
      want = %{wanted_since: at(now, -@hour), last_searched_at: at(now, -31 * 60)}
      assert WantSchedule.due?(want, now)
    end

    test "an aged want waits its whole band; nothing forces it early" do
      now = DateTime.utc_now()
      # 50h-old want → 4h band. Searched 3h ago: still waiting.
      want = %{wanted_since: at(now, -50 * @hour), last_searched_at: at(now, -3 * @hour)}
      refute WantSchedule.due?(want, now)
    end
  end
end
