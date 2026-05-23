defmodule MediaCentaur.Console.BufferTest do
  use MediaCentaur.DataCase, async: false

  alias MediaCentaur.Console.{Buffer, Entry, Filter}
  alias MediaCentaur.Topics

  # Build a minimal valid Entry for tests.
  defp build_entry(opts \\ []) do
    %Entry{
      id: Keyword.get(opts, :id, System.unique_integer([:monotonic, :positive])),
      timestamp: DateTime.utc_now(),
      level: Keyword.get(opts, :level, :info),
      component: Keyword.get(opts, :component, :system),
      message: Keyword.get(opts, :message, "test message"),
      module: nil,
      metadata: %{}
    }
  end

  # Start a buffer with a unique name so tests don't collide.
  defp start_buffer(opts \\ []) do
    name = :"test_buffer_#{:erlang.unique_integer([:positive])}"
    full_opts = Keyword.merge([name: name], opts)
    pid = start_supervised!({Buffer, full_opts})
    {pid, name}
  end

  describe "start_link + append + recent" do
    test "entries come back newest-first" do
      {_pid, name} = start_buffer()

      first = build_entry(id: 1, message: "first")
      second = build_entry(id: 2, message: "second")
      third = build_entry(id: 3, message: "third")

      Buffer.append(first, name)
      Buffer.append(second, name)
      Buffer.append(third, name)

      entries = Buffer.recent(nil, name)

      assert length(entries) == 3
      assert Enum.at(entries, 0).message == "third"
      assert Enum.at(entries, 1).message == "second"
      assert Enum.at(entries, 2).message == "first"
    end
  end

  describe "append past cap" do
    test "oldest entries are dropped when cap is exceeded" do
      {_pid, name} = start_buffer(cap: 3)

      for i <- 1..5 do
        Buffer.append(build_entry(id: i, message: "msg #{i}"), name)
      end

      entries = Buffer.recent(nil, name)

      assert length(entries) == 3
      messages = Enum.map(entries, & &1.message)
      assert "msg 5" in messages
      assert "msg 4" in messages
      assert "msg 3" in messages
      refute "msg 2" in messages
      refute "msg 1" in messages
    end
  end

  describe "snapshot/1" do
    test "returns expected map shape" do
      {_pid, name} = start_buffer()
      entry = build_entry()
      Buffer.append(entry, name)

      snapshot = Buffer.snapshot(name)

      assert is_map(snapshot)
      assert Map.has_key?(snapshot, :entries)
      assert Map.has_key?(snapshot, :cap)
      assert Map.has_key?(snapshot, :filter)
      assert is_list(snapshot.entries)
      assert is_integer(snapshot.cap)
      assert %Filter{} = snapshot.filter
      assert length(snapshot.entries) == 1
    end
  end

  describe "clear/1" do
    test "wipes entries and broadcasts :buffer_cleared" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      Buffer.append(build_entry(), name)
      assert length(Buffer.recent(nil, name)) == 1

      Buffer.clear(name)

      assert Buffer.recent(nil, name) == []
      assert_receive :buffer_cleared, 500
    end
  end

  describe "resize/2" do
    test "shrinking cap truncates existing entries immediately" do
      # Start with a large enough cap to hold the test-only warm-up entries,
      # then shrink to a valid cap below the current entry count to exercise
      # the immediate-truncation path inside handle_call({:resize, _}, _, _).
      {_pid, name} = start_buffer(cap: 500)

      for i <- 1..400 do
        Buffer.append(build_entry(id: i), name)
      end

      assert length(Buffer.recent(nil, name)) == 400

      # Shrink BELOW current count — resize must drop the oldest 300
      # entries in place, not just cap future appends.
      Buffer.resize(100, name)

      recent_after_shrink = Buffer.recent(nil, name)
      assert length(recent_after_shrink) == 100
      # The newest 100 entries (ids 301..400) must remain; oldest dropped.
      assert hd(recent_after_shrink).id == 400
      assert List.last(recent_after_shrink).id == 301
    end

    test "growing cap accepts more entries after being capped" do
      {_pid, name} = start_buffer(cap: 100)

      for i <- 1..100 do
        Buffer.append(build_entry(id: i), name)
      end

      assert length(Buffer.recent(nil, name)) == 100

      Buffer.resize(500, name)

      for i <- 101..300 do
        Buffer.append(build_entry(id: i), name)
      end

      assert length(Buffer.recent(nil, name)) == 300
    end

    test "broadcasts {:buffer_resized, n} on resize" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      Buffer.resize(500, name)

      assert_receive {:buffer_resized, 500}, 500
    end

    test "returns error for value below minimum cap" do
      {_pid, name} = start_buffer()

      result = Buffer.resize(99, name)

      assert {:error, _reason} = result
    end

    test "returns error for value above maximum cap" do
      {_pid, name} = start_buffer()

      result = Buffer.resize(50_001, name)

      assert {:error, _reason} = result
    end
  end

  describe "put_filter/2 + get_filter/1" do
    test "round-trip: set filter and read it back" do
      {_pid, name} = start_buffer()

      new_filter = Filter.new(level: :error, search: "boom")
      Buffer.put_filter(new_filter, name)

      returned_filter = Buffer.get_filter(name)

      assert returned_filter.level == :error
      assert returned_filter.search == "boom"
    end

    test "broadcasts {:filter_changed, filter} when filter is updated" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      new_filter = Filter.new(level: :warning)
      Buffer.put_filter(new_filter, name)

      assert_receive {:filter_changed, ^new_filter}, 500
    end
  end

  describe "PubSub broadcast on append" do
    test "broadcasts {:log_entry, entry} when an entry is appended" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      entry = build_entry(message: "pubsub test")
      Buffer.append(entry, name)

      assert_receive {:log_entry, ^entry}, 500
    end
  end

  describe "persistence debounce" do
    test "sending :persist writes the filter to Settings" do
      {pid, name} = start_buffer()

      # Allow the Buffer GenServer process to use this test's DB connection.
      Ecto.Adapters.SQL.Sandbox.allow(MediaCentaur.Repo, self(), pid)

      new_filter = Filter.new(level: :debug)
      Buffer.put_filter(new_filter, name)

      # Verify filter is set in memory without waiting for the debounce timer.
      assert Buffer.get_filter(name).level == :debug

      # Force persist by sending the :persist message directly, bypassing the timer.
      send(pid, :persist)

      # Sync: issue a call that will only complete after :persist has been processed.
      Buffer.snapshot(name)

      # Now verify the settings row exists.
      {:ok, settings_entry} = MediaCentaur.Settings.get_by_key("console_filter")
      assert settings_entry != nil
      assert is_map(settings_entry.value)
      assert Map.get(settings_entry.value, "level") == "debug"
    end
  end

  describe "init with missing Settings keys" do
    test "buffer starts with defaults when Settings keys are absent" do
      # Start a fresh buffer — Settings keys may or may not be present,
      # but the buffer must always start without crashing and with valid defaults.
      {_pid, name} = start_buffer()

      snapshot = Buffer.snapshot(name)

      # cap defaults to 2_000 (or whatever was persisted; just check it's in range)
      assert snapshot.cap >= 100
      assert snapshot.cap <= 50_000
      assert %Filter{} = snapshot.filter
    end
  end

  describe "append crash-safety" do
    test "append/2 with a non-existent name is a no-op and does not crash" do
      result = Buffer.append(build_entry(), :nonexistent_buffer_name)
      assert result == :ok
    end
  end

  describe "recent/2 with limit" do
    test "returns at most n entries" do
      {_pid, name} = start_buffer()

      for i <- 1..10 do
        Buffer.append(build_entry(id: i), name)
      end

      entries = Buffer.recent(3, name)

      assert length(entries) == 3
    end
  end
end
