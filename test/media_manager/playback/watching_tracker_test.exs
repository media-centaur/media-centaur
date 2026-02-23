defmodule MediaManager.Playback.WatchingTrackerTest do
  use ExUnit.Case, async: true

  alias MediaManager.Playback.WatchingTracker

  describe "new/0" do
    test "returns initial state" do
      tracker = WatchingTracker.new()
      assert tracker.previous_position == nil
      assert tracker.continuous_since == nil
      assert tracker.actively_watching == false
      assert tracker.saveable_position == nil
    end
  end

  describe "first update" do
    test "initializes previous_position and continuous_since without treating as seek" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 10.0, 1000)

      assert tracker.previous_position == 10.0
      assert tracker.continuous_since == 1000
      assert tracker.actively_watching == false
      assert tracker.saveable_position == nil
    end
  end

  describe "continuous playback" do
    test "does not set actively_watching before 20 seconds" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      # Simulate 19 seconds of 1-second ticks
      tracker =
        Enum.reduce(1..19, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, second * 1.0, second * 1000)
        end)

      assert tracker.actively_watching == false
      assert tracker.saveable_position == nil
    end

    test "sets actively_watching after 20 seconds of continuous playback" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      # Simulate 21 seconds of 1-second ticks
      tracker =
        Enum.reduce(1..21, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, second * 1.0, second * 1000)
        end)

      assert tracker.actively_watching == true
      assert tracker.saveable_position == 21.0
    end

    test "advances saveable_position with each tick after threshold" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      # Get to actively_watching
      tracker =
        Enum.reduce(1..25, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, second * 1.0, second * 1000)
        end)

      assert tracker.saveable_position == 25.0

      # A few more ticks
      tracker = WatchingTracker.update(tracker, 26.0, 26_000)
      assert tracker.saveable_position == 26.0

      tracker = WatchingTracker.update(tracker, 27.0, 27_000)
      assert tracker.saveable_position == 27.0
    end
  end

  describe "seek detection" do
    test "position jump > 3 seconds resets continuous timer" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 10.0, 0)
      tracker = WatchingTracker.update(tracker, 11.0, 1000)

      # Seek forward by 30 seconds
      tracker = WatchingTracker.update(tracker, 41.0, 2000)

      assert tracker.actively_watching == false
      assert tracker.continuous_since == nil
      assert tracker.previous_position == 41.0
    end

    test "seek backward resets continuous timer" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 100.0, 0)
      tracker = WatchingTracker.update(tracker, 101.0, 1000)

      # Seek backward
      tracker = WatchingTracker.update(tracker, 50.0, 2000)

      assert tracker.actively_watching == false
      assert tracker.continuous_since == nil
    end

    test "seek does not update saveable_position" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      # Get to actively_watching
      tracker =
        Enum.reduce(1..25, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, second * 1.0, second * 1000)
        end)

      assert tracker.saveable_position == 25.0

      # Seek — saveable_position should NOT change
      tracker = WatchingTracker.update(tracker, 100.0, 26_000)

      assert tracker.saveable_position == 25.0
      assert tracker.actively_watching == false
    end

    test "multiple seeks never set actively_watching" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      # Seek around many times, never watching continuously
      tracker = WatchingTracker.update(tracker, 30.0, 1000)
      tracker = WatchingTracker.update(tracker, 60.0, 2000)
      tracker = WatchingTracker.update(tracker, 10.0, 3000)
      tracker = WatchingTracker.update(tracker, 90.0, 4000)
      tracker = WatchingTracker.update(tracker, 5.0, 5000)

      assert tracker.actively_watching == false
      assert tracker.saveable_position == nil
    end
  end

  describe "resume after seek" do
    test "20 more seconds of continuous watching re-enables saving" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      # Get to actively_watching
      tracker =
        Enum.reduce(1..25, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, second * 1.0, second * 1000)
        end)

      assert tracker.actively_watching == true
      last_saveable = tracker.saveable_position

      # Seek
      tracker = WatchingTracker.update(tracker, 500.0, 26_000)
      assert tracker.actively_watching == false
      assert tracker.saveable_position == last_saveable

      # Resume watching from 500 for 20+ seconds
      tracker =
        Enum.reduce(1..21, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, 500.0 + second, 26_000 + second * 1000)
        end)

      assert tracker.actively_watching == true
      assert tracker.saveable_position == 521.0
    end
  end

  describe "edge cases" do
    test "position jump of exactly 3.0 is NOT a seek" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 10.0, 0)

      # Exactly 3.0 second jump — not a seek (threshold is >3.0)
      tracker = WatchingTracker.update(tracker, 13.0, 1000)

      assert tracker.continuous_since == 0
    end

    test "position jump of 3.01 IS a seek" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 10.0, 0)

      tracker = WatchingTracker.update(tracker, 13.01, 1000)

      assert tracker.continuous_since == nil
    end

    test "saveable_position stays nil until threshold reached" do
      tracker = WatchingTracker.new()
      tracker = WatchingTracker.update(tracker, 0.0, 0)

      tracker =
        Enum.reduce(1..19, tracker, fn second, tracker ->
          WatchingTracker.update(tracker, second * 1.0, second * 1000)
        end)

      assert tracker.saveable_position == nil
    end
  end
end
