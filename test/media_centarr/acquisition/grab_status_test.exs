defmodule MediaCentarr.Acquisition.GrabStatusTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Acquisition.GrabStatus

  describe "buckets" do
    test "every known status is in exactly one bucket" do
      # The bug shape: a status leaks out of a bucket and is silently
      # treated as belonging to another. Pin the partition.
      buckets =
        Enum.map(GrabStatus.all(), fn status ->
          {status, GrabStatus.bucket(status)}
        end)

      assert Enum.uniq(GrabStatus.all()) == GrabStatus.all()
      assert Enum.all?(buckets, fn {_, b} -> b in [:in_flight, :terminal_success, :terminal_failure] end)
    end

    test "in_flight covers searching and snoozed only" do
      assert "searching" in GrabStatus.in_flight()
      assert "snoozed" in GrabStatus.in_flight()
      assert length(GrabStatus.in_flight()) == 2
    end

    test "terminal covers grabbed, abandoned, and cancelled" do
      assert "grabbed" in GrabStatus.terminal()
      assert "abandoned" in GrabStatus.terminal()
      assert "cancelled" in GrabStatus.terminal()
      assert length(GrabStatus.terminal()) == 3
    end

    test "terminal_failure (rearmable) covers cancelled and abandoned only" do
      # Regression for v0.31.0: the original bug was treating these as
      # in-flight and silently no-op'ing the user's "Queue all" action.
      assert "cancelled" in GrabStatus.terminal_failure()
      assert "abandoned" in GrabStatus.terminal_failure()
      refute "grabbed" in GrabStatus.terminal_failure()
      refute "searching" in GrabStatus.terminal_failure()
      refute "snoozed" in GrabStatus.terminal_failure()
    end
  end

  describe "predicates" do
    test "in_flight? returns true for live job statuses" do
      assert GrabStatus.in_flight?("searching")
      assert GrabStatus.in_flight?("snoozed")
      refute GrabStatus.in_flight?("grabbed")
      refute GrabStatus.in_flight?("abandoned")
      refute GrabStatus.in_flight?("cancelled")
    end

    test "terminal? returns true for all terminal statuses" do
      refute GrabStatus.terminal?("searching")
      refute GrabStatus.terminal?("snoozed")
      assert GrabStatus.terminal?("grabbed")
      assert GrabStatus.terminal?("abandoned")
      assert GrabStatus.terminal?("cancelled")
    end

    test "rearmable? returns true only for cancelled and abandoned" do
      refute GrabStatus.rearmable?("searching")
      refute GrabStatus.rearmable?("snoozed")
      refute GrabStatus.rearmable?("grabbed")
      assert GrabStatus.rearmable?("abandoned")
      assert GrabStatus.rearmable?("cancelled")
    end

    test "predicates accept atoms as well as strings" do
      assert GrabStatus.in_flight?(:searching)
      assert GrabStatus.terminal?(:grabbed)
      assert GrabStatus.rearmable?(:cancelled)
    end
  end

  describe "bucket/1" do
    test "raises ArgumentError on unknown status — by design" do
      # Unknown status is a bug, not a runtime condition. Crash loud.
      assert_raise ArgumentError, ~r/unknown grab status/, fn ->
        GrabStatus.bucket("not-a-real-status")
      end
    end
  end
end
