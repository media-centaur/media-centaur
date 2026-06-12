defmodule MediaCentaur.ReleaseTracking.RefreshScheduleTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.ReleaseTracking.RefreshSchedule

  describe "next_delay_ms/2" do
    test "returns 0 when last completion is nil — i.e. never run before" do
      assert RefreshSchedule.next_delay_ms(nil, :timer.minutes(15)) == 0
    end

    test "returns the full interval when no time has passed since last completion" do
      now = ~U[2026-06-12 12:00:00.000Z]
      interval = :timer.minutes(15)

      assert RefreshSchedule.next_delay_ms(now, interval, now) == interval
    end

    test "returns 0 when more time than interval has elapsed (regression: timer reset on restart)" do
      twenty_five_hours_ago = DateTime.add(DateTime.utc_now(), -25 * 60 * 60, :second)
      assert RefreshSchedule.next_delay_ms(twenty_five_hours_ago, :timer.hours(24)) == 0
    end

    test "returns the remaining ms when partial interval has elapsed" do
      now = ~U[2026-06-12 12:00:00.000Z]
      five_minutes_ago = DateTime.add(now, -5 * 60, :second)
      interval = :timer.minutes(15)

      assert RefreshSchedule.next_delay_ms(five_minutes_ago, interval, now) == :timer.minutes(10)
    end
  end
end
