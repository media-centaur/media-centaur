defmodule MediaCentaur.ErrorReports.PersistThrottleTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Console.Entry
  alias MediaCentaur.ErrorReports.PersistThrottle

  @window 1_000

  defp entry(message) do
    Entry.new(%{
      id: System.unique_integer([:positive]),
      timestamp: DateTime.utc_now(),
      level: :error,
      component: :tmdb,
      message: message
    })
  end

  describe "record/5" do
    test "persists the first occurrence of a fingerprint immediately" do
      assert {:persist_now, state} =
               PersistThrottle.record(PersistThrottle.new(), "fp", entry("a"), 0, @window)

      assert state.last["fp"] == 0
      assert state.pending == %{}
    end

    test "defers and coalesces occurrences within the window" do
      state = PersistThrottle.new()
      {:persist_now, state} = PersistThrottle.record(state, "fp", entry("a"), 0, @window)
      {:defer, state} = PersistThrottle.record(state, "fp", entry("b"), 200, @window)
      {:defer, state} = PersistThrottle.record(state, "fp", entry("c"), 400, @window)

      assert {_entry, 2} = state.pending["fp"]
    end

    test "persists again once the window has elapsed" do
      state = PersistThrottle.new()
      {:persist_now, state} = PersistThrottle.record(state, "fp", entry("a"), 0, @window)
      {:persist_now, state} = PersistThrottle.record(state, "fp", entry("b"), 1_000, @window)

      assert state.last["fp"] == 1_000
      assert state.pending == %{}
    end

    test "tracks distinct fingerprints independently" do
      state = PersistThrottle.new()
      {:persist_now, state} = PersistThrottle.record(state, "a", entry("a"), 0, @window)
      {:persist_now, state} = PersistThrottle.record(state, "b", entry("b"), 100, @window)

      assert Enum.sort(Map.keys(state.last)) == ["a", "b"]
    end
  end

  describe "flush_due/3" do
    test "emits one write per pending fingerprint carrying the coalesced count" do
      state = PersistThrottle.new()
      {:persist_now, state} = PersistThrottle.record(state, "fp", entry("a"), 0, @window)
      {:defer, state} = PersistThrottle.record(state, "fp", entry("b"), 100, @window)
      {:defer, state} = PersistThrottle.record(state, "fp", entry("c"), 200, @window)

      {writes, state} = PersistThrottle.flush_due(state, 300, @window)

      assert [{%Entry{message: "c"}, 2}] = writes
      assert state.pending == %{}
      assert state.last["fp"] == 300
    end

    test "prunes fingerprints idle longer than the window so last stays bounded" do
      state = PersistThrottle.new()
      {:persist_now, state} = PersistThrottle.record(state, "stale", entry("a"), 0, @window)
      {:persist_now, state} = PersistThrottle.record(state, "fresh", entry("b"), 900, @window)

      {[], state} = PersistThrottle.flush_due(state, 1_000, @window)

      # "stale" last write was at 0, now 1000 → idle == window → pruned.
      refute Map.has_key?(state.last, "stale")
      # "fresh" at 900, now 1000 → idle 100 → kept.
      assert state.last["fresh"] == 900
    end
  end
end
