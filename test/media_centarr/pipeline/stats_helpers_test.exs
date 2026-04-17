defmodule MediaCentarr.Pipeline.StatsHelpersTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Pipeline.StatsHelpers

  describe "prune_window/3" do
    test "removes completions older than window" do
      now = 10_000
      window_ms = 5_000

      completions = [
        {3_000, 100},
        {6_000, 200},
        {8_000, 150}
      ]

      assert StatsHelpers.prune_window(completions, now, window_ms) == [
               {6_000, 200},
               {8_000, 150}
             ]
    end

    test "keeps completions exactly at cutoff boundary" do
      now = 10_000
      window_ms = 5_000

      completions = [{5_000, 100}, {7_000, 200}]

      assert StatsHelpers.prune_window(completions, now, window_ms) == [
               {5_000, 100},
               {7_000, 200}
             ]
    end

    test "returns empty list when all completions are stale" do
      assert StatsHelpers.prune_window([{1, 100}, {2, 200}], 10_000, 5_000) == []
    end

    test "returns empty list for empty input" do
      assert StatsHelpers.prune_window([], 10_000, 5_000) == []
    end
  end

  describe "calculate_throughput/2" do
    test "returns 0.0 for empty completions" do
      assert StatsHelpers.calculate_throughput([], 5_000) == 0.0
    end

    test "calculates events per second" do
      completions = [{1, 100}, {2, 200}, {3, 300}, {4, 400}, {5, 500}]
      # 5 events in a 10_000ms (10s) window = 0.5/s
      assert StatsHelpers.calculate_throughput(completions, 10_000) == 0.5
    end

    test "rounds to one decimal place" do
      completions = [{1, 100}, {2, 200}, {3, 300}]
      # 3 events in 10_000ms = 0.3/s
      assert StatsHelpers.calculate_throughput(completions, 10_000) == 0.3
    end
  end

  describe "calculate_avg_duration/1" do
    test "returns nil for empty completions" do
      assert StatsHelpers.calculate_avg_duration([]) == nil
    end

    test "calculates average duration in milliseconds" do
      # Use native time units for durations
      ms_to_native = fn ms ->
        System.convert_time_unit(ms, :millisecond, :native)
      end

      completions = [
        {1, ms_to_native.(100)},
        {2, ms_to_native.(200)},
        {3, ms_to_native.(300)}
      ]

      assert StatsHelpers.calculate_avg_duration(completions) == 200.0
    end

    test "single completion returns its own duration" do
      ms_to_native = fn ms ->
        System.convert_time_unit(ms, :millisecond, :native)
      end

      completions = [{1, ms_to_native.(500)}]
      assert StatsHelpers.calculate_avg_duration(completions) == 500.0
    end
  end

  describe "derive_status/5" do
    test "returns :idle when no active items and no errors" do
      assert StatsHelpers.derive_status(0, nil, 10_000, 5_000, 3) == :idle
    end

    test "returns :active with work in progress" do
      assert StatsHelpers.derive_status(1, nil, 10_000, 5_000, 3) == :active
    end

    test "returns :saturated when active count meets threshold" do
      assert StatsHelpers.derive_status(3, nil, 10_000, 5_000, 3) == :saturated
    end

    test "returns :saturated when active count exceeds threshold" do
      assert StatsHelpers.derive_status(5, nil, 10_000, 5_000, 3) == :saturated
    end

    test "returns :erroring when active with recent error" do
      now = 10_000
      last_error = {"something failed", 8_000}
      assert StatsHelpers.derive_status(1, last_error, now, 5_000, 3) == :erroring
    end

    test "returns :active when error is outside window" do
      now = 10_000
      last_error = {"something failed", 2_000}
      assert StatsHelpers.derive_status(1, last_error, now, 5_000, 3) == :active
    end

    test "returns :idle when no active items even with recent error" do
      now = 10_000
      last_error = {"something failed", 8_000}
      assert StatsHelpers.derive_status(0, last_error, now, 5_000, 3) == :idle
    end
  end

  describe "format_error_reason/1" do
    test "returns binary reasons as-is" do
      assert StatsHelpers.format_error_reason("timeout") == "timeout"
    end

    test "inspects non-binary reasons" do
      assert StatsHelpers.format_error_reason(:timeout) == ":timeout"
    end

    test "inspects tuple reasons" do
      assert StatsHelpers.format_error_reason({:error, :nxdomain}) == "{:error, :nxdomain}"
    end
  end
end
