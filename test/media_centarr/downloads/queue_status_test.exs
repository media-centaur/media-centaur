defmodule MediaCentarr.Downloads.QueueStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Downloads.{QueueState, QueueStatus}

  @cadence_ms 1500

  describe "derive/3" do
    test ":initializing when no successful poll and no error yet" do
      state = %QueueState{}
      assert QueueStatus.derive(state, @cadence_ms) == :initializing
    end

    test ":not_configured when last_error is :not_configured" do
      state = %QueueState{last_error: :not_configured}
      assert QueueStatus.derive(state, @cadence_ms) == :not_configured
    end

    test ":auth_failed when last_error is :auth_failed" do
      state = %QueueState{last_error: :auth_failed, last_successful_poll_at: DateTime.utc_now()}
      assert QueueStatus.derive(state, @cadence_ms) == :auth_failed
    end

    test ":live when last successful poll is within 2x cadence" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -1500, :millisecond)
      state = %QueueState{last_successful_poll_at: recent}

      assert QueueStatus.derive(state, @cadence_ms, now) == :live
    end

    test "{:lagging, age_ms} when last successful poll is between 2x and 5x cadence" do
      now = DateTime.utc_now()
      stale = DateTime.add(now, -4500, :millisecond)
      state = %QueueState{last_successful_poll_at: stale}

      assert {:lagging, age} = QueueStatus.derive(state, @cadence_ms, now)
      assert_in_delta age, 4500, 50
    end

    test "{:offline, since} when last successful poll exceeds 5x cadence" do
      now = DateTime.utc_now()
      ancient = DateTime.add(now, -8000, :millisecond)
      state = %QueueState{last_successful_poll_at: ancient}

      assert {:offline, ^ancient} = QueueStatus.derive(state, @cadence_ms, now)
    end

    test "{:offline, since} explicit error overrides age classification" do
      now = DateTime.utc_now()
      since = DateTime.add(now, -2000, :millisecond)
      state = %QueueState{last_error: {:offline, since}, last_successful_poll_at: now}

      assert QueueStatus.derive(state, @cadence_ms, now) == {:offline, since}
    end
  end
end
