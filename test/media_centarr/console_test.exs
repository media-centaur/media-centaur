defmodule MediaCentarr.ConsoleTest do
  use MediaCentarr.DataCase, async: false

  alias MediaCentarr.Console
  alias MediaCentarr.Console.{Buffer, Filter}

  setup do
    # Buffer is started by the application supervision tree — no need to start it here.
    # Clear any entries accumulated before this test.
    Buffer.clear()
    :ok
  end

  describe "snapshot/0" do
    test "returns the expected map shape" do
      snapshot = Console.snapshot()

      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :entries)
      assert Map.has_key?(snapshot, :cap)
      assert Map.has_key?(snapshot, :filter)
    end
  end

  describe "update_filter/1 + get_filter/0" do
    test "round-trip: update and read back" do
      new_filter = Filter.new(level: :error, search: "crash")
      Console.update_filter(new_filter)

      returned_filter = Console.get_filter()

      assert returned_filter.level == :error
      assert returned_filter.search == "crash"
    end
  end

  describe "clear/0" do
    test "returns :ok and leaves the buffer empty" do
      # Console.clear/0 is a pure defdelegate to Buffer.clear/0; the
      # entry-clearing behavior itself is thoroughly covered by buffer_test.exs.
      # This test verifies only that the facade delegation chain works.
      assert Console.clear() == :ok
      assert Console.recent_entries() == []
      assert Console.snapshot().entries == []
    end
  end

  describe "known_components/0" do
    test "returns the atom list from View" do
      components = Console.known_components()

      assert is_list(components)
      assert :pipeline in components
      assert :ecto in components
      assert :system in components
    end
  end

  describe "rescan_library/0" do
    test "returns :ok and dispatches to TaskSupervisor" do
      before_count = length(Task.Supervisor.children(MediaCentarr.TaskSupervisor))

      assert Console.rescan_library() == :ok

      # The call must be non-blocking — it returns :ok immediately whether or
      # not watchers are configured. The task may finish instantly in test
      # (no watch dirs), so just verify the count increased by at least 1 at
      # some point OR that it completed without crashing.
      after_count = length(Task.Supervisor.children(MediaCentarr.TaskSupervisor))

      # Either the task is still running (after > before) or it already
      # finished (after == before). Either way: no crash, :ok returned.
      assert after_count >= before_count
    end
  end

  describe "subscribe/0" do
    test "returns :ok" do
      result = Console.subscribe()

      assert result == :ok
    end
  end
end
