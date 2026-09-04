defmodule MediaCentaur.FormatTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Format

  describe "format_seconds/1" do
    test "returns 0:00 for nil" do
      assert Format.format_seconds(nil) == "0:00"
    end

    test "formats zero seconds" do
      assert Format.format_seconds(0) == "0:00"
    end

    test "formats seconds under a minute" do
      assert Format.format_seconds(45) == "0:45"
    end

    test "pads single-digit seconds" do
      assert Format.format_seconds(63) == "1:03"
    end

    test "formats minutes and seconds" do
      assert Format.format_seconds(754) == "12:34"
    end

    test "formats hours with padded minutes and seconds" do
      assert Format.format_seconds(3661) == "1:01:01"
    end

    test "formats multi-hour duration" do
      assert Format.format_seconds(7384) == "2:03:04"
    end

    test "truncates fractional seconds" do
      assert Format.format_seconds(90.7) == "1:30"
    end
  end

  describe "short_id/1" do
    test "returns first 8 characters of a UUID" do
      assert Format.short_id("550e8400-e29b-41d4-a716-446655440000") == "550e8400"
    end

    test "handles short strings" do
      assert Format.short_id("abc") == "abc"
    end
  end

  describe "relative_in/1" do
    test "nil returns \"unknown\"" do
      assert Format.relative_in(nil) == "unknown"
    end

    test "now or past returns \"any moment now\"" do
      now = DateTime.utc_now()
      assert Format.relative_in(now) == "any moment now"
      assert Format.relative_in(DateTime.add(now, -30, :second)) == "any moment now"
    end

    test "sub-minute future returns \"in <N>s\"" do
      future = DateTime.add(DateTime.utc_now(), 45, :second)
      assert Format.relative_in(future) == "in 45s"
    end

    test "sub-hour future returns \"in <N>m\"" do
      future = DateTime.add(DateTime.utc_now(), 23 * 60, :second)
      assert Format.relative_in(future) == "in 23m"
    end

    test "hour-plus future returns \"in <H>h <M>m\" with minute precision" do
      future = DateTime.add(DateTime.utc_now(), 2 * 3600 + 15 * 60, :second)
      assert Format.relative_in(future) == "in 2h 15m"
    end

    test "exact-hour future drops the minute fragment" do
      future = DateTime.add(DateTime.utc_now(), 3 * 3600, :second)
      assert Format.relative_in(future) == "in 3h"
    end

    test "day-plus future returns \"in <D>d <H>h\"" do
      future = DateTime.add(DateTime.utc_now(), 2 * 86_400 + 5 * 3600, :second)
      assert Format.relative_in(future) == "in 2d 5h"
    end

    test "exact-day future drops the hour fragment" do
      future = DateTime.add(DateTime.utc_now(), 4 * 86_400, :second)
      assert Format.relative_in(future) == "in 4d"
    end
  end

  describe "format_size_decimal/1" do
    test "nil returns nil" do
      assert Format.format_size_decimal(nil) == nil
    end

    test "sub-megabyte returns bytes" do
      assert Format.format_size_decimal(512) == "512 B"
    end

    test "megabyte range returns whole MB (decimal)" do
      assert Format.format_size_decimal(5_000_000) == "5 MB"
    end

    test "gigabyte range returns one-decimal GB (decimal, indexer convention)" do
      assert Format.format_size_decimal(1_500_000_000) == "1.5 GB"
    end
  end

  describe "elapsed/2" do
    @now ~U[2026-09-04 12:00:00Z]

    test "seconds, minutes, hours and days at their coarsest whole unit" do
      assert Format.elapsed(~U[2026-09-04 11:59:18Z], @now) == "42s"
      assert Format.elapsed(~U[2026-09-04 11:57:00Z], @now) == "3m"
      assert Format.elapsed(~U[2026-09-04 09:30:00Z], @now) == "2h"
      assert Format.elapsed(~U[2026-09-02 12:00:00Z], @now) == "2d"
    end

    test "a moment in the future reads as no time at all" do
      assert Format.elapsed(~U[2026-09-04 12:00:05Z], @now) == "0s"
    end
  end

  describe "relative_ago/2" do
    test "nil returns \"never\"" do
      assert Format.relative_ago(nil) == "never"
    end

    test "defaults to seconds granularity under a minute" do
      assert Format.relative_ago(DateTime.add(DateTime.utc_now(), -10, :second)) == "10s ago"
    end

    test "sub_minute: :just_now collapses the first minute to \"just now\"" do
      ten_seconds_ago = DateTime.add(DateTime.utc_now(), -10, :second)
      assert Format.relative_ago(ten_seconds_ago, sub_minute: :just_now) == "just now"
    end

    test "minute/hour/day granularity is identical regardless of sub_minute" do
      now = DateTime.utc_now()
      assert Format.relative_ago(DateTime.add(now, -90, :second)) == "1m ago"
      assert Format.relative_ago(DateTime.add(now, -3 * 3600, :second)) == "3h ago"

      assert Format.relative_ago(DateTime.add(now, -2 * 86_400, :second), sub_minute: :just_now) ==
               "2d ago"
    end
  end
end
