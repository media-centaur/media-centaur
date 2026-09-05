defmodule MediaCentaur.ReleaseTracking.RefreshScheduleTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.RefreshSchedule

  describe "next_delay_ms/2" do
    test "returns 0 when last completion is nil — i.e. never run before" do
      assert RefreshSchedule.next_delay_ms(nil, to_timeout(minute: 15)) == 0
    end

    test "returns the full interval when no time has passed since last completion" do
      now = ~U[2026-06-12 12:00:00.000Z]
      interval = to_timeout(minute: 15)

      assert RefreshSchedule.next_delay_ms(now, interval, now) == interval
    end

    test "returns 0 when more time than interval has elapsed (regression: timer reset on restart)" do
      twenty_five_hours_ago = DateTime.add(DateTime.utc_now(), -25 * 60 * 60, :second)
      assert RefreshSchedule.next_delay_ms(twenty_five_hours_ago, to_timeout(day: 1)) == 0
    end

    test "never schedules sooner than the floor — a restarted loop must not tick at once" do
      now = ~U[2026-09-05 12:00:00Z]
      overdue = ~U[2026-09-05 10:00:00Z]

      assert RefreshSchedule.next_delay_ms(nil, 60_000, now, floor_ms: 5_000) == 5_000
      assert RefreshSchedule.next_delay_ms(overdue, 60_000, now, floor_ms: 5_000) == 5_000
      assert RefreshSchedule.next_delay_ms(now, 60_000, now, floor_ms: 5_000) == 60_000
    end

    test "returns the remaining ms when partial interval has elapsed" do
      now = ~U[2026-06-12 12:00:00.000Z]
      five_minutes_ago = DateTime.add(now, -5 * 60, :second)
      interval = to_timeout(minute: 15)

      assert RefreshSchedule.next_delay_ms(five_minutes_ago, interval, now) == to_timeout(minute: 10)
    end
  end
end
