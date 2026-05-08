defmodule MediaCentarr.ReleaseTracking.RefreshScheduleTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.ReleaseTracking.RefreshSchedule

  describe "next_delay_ms/2" do
    test "returns 0 when last completion is nil — i.e. never run before" do
      assert RefreshSchedule.next_delay_ms(nil, :timer.minutes(15)) == 0
    end

    test "returns the full interval when no time has passed since last completion" do
      now = DateTime.utc_now()
      interval = :timer.minutes(15)

      delay = RefreshSchedule.next_delay_ms(now, interval)

      assert delay > interval - 100
      assert delay <= interval
    end

    test "returns 0 when more time than interval has elapsed (regression: timer reset on restart)" do
      twenty_five_hours_ago = DateTime.add(DateTime.utc_now(), -25 * 60 * 60, :second)
      assert RefreshSchedule.next_delay_ms(twenty_five_hours_ago, :timer.hours(24)) == 0
    end

    test "returns the remaining ms when partial interval has elapsed" do
      five_minutes_ago = DateTime.add(DateTime.utc_now(), -5 * 60, :second)
      interval = :timer.minutes(15)

      delay = RefreshSchedule.next_delay_ms(five_minutes_ago, interval)

      assert_in_delta delay, :timer.minutes(10), 100
    end
  end
end
