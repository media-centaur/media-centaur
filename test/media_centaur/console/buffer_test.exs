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

  describe "start_link + append + read" do
    test "entries come back newest-first" do
      {_pid, name} = start_buffer()

      first = build_entry(id: 1, message: "first")
      second = build_entry(id: 2, message: "second")
      third = build_entry(id: 3, message: "third")

      Buffer.append(first, name)
      Buffer.append(second, name)
      Buffer.append(third, name)

      entries = Buffer.read(Filter.all(), 1_000, name)

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

      entries = Buffer.read(Filter.all(), 1_000, name)

      assert length(entries) == 3
      messages = Enum.map(entries, & &1.message)
      assert "msg 5" in messages
      assert "msg 4" in messages
      assert "msg 3" in messages
      refute "msg 2" in messages
      refute "msg 1" in messages
    end
  end

  describe "clear/1" do
    test "wipes entries and broadcasts :buffer_cleared" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      Buffer.append(build_entry(), name)
      assert length(Buffer.read(Filter.all(), 1_000, name)) == 1

      Buffer.clear(name)

      assert Buffer.read(Filter.all(), 1_000, name) == []
      assert_receive :buffer_cleared, 500
    end
  end

  describe "reset/1" do
    test "drops a pending settings write, where clear/1 keeps it" do
      # A short debounce so the timer fires inside this test.
      {pid, name} = start_buffer(cap: 500, persist_debounce_ms: 30)
      Ecto.Adapters.SQL.Sandbox.allow(MediaCentaur.Repo, self(), pid)

      :ok = Buffer.resize(200, name)
      Buffer.clear(name)

      # clear/1 keeps the pending write: a person emptying the console has
      # not changed their mind about its size.
      eventually(fn ->
        match?(%{value: %{"value" => 200}}, MediaCentaur.Settings.get_by_key("console_buffer_size")) ||
          nil
      end)

      :ok = Buffer.resize(300, name)
      Buffer.append(build_entry(), name)
      Buffer.reset(name)

      # A negative needs a bounded wait: an uncancelled timer would have
      # fired well within it.
      Process.sleep(150)
      assert %{value: %{"value" => 200}} = MediaCentaur.Settings.get_by_key("console_buffer_size")
      assert Buffer.read(Filter.all(), 1_000, name) == []
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

      assert length(Buffer.read(Filter.all(), 1_000, name)) == 400

      # Shrink BELOW current count — resize must drop the oldest 300
      # entries in place, not just cap future appends.
      Buffer.resize(100, name)

      after_shrink = Buffer.read(Filter.all(), 1_000, name)
      assert length(after_shrink) == 100
      # The newest 100 entries (ids 301..400) must remain; oldest dropped.
      assert hd(after_shrink).id == 400
      assert List.last(after_shrink).id == 301
    end

    test "growing cap accepts more entries after being capped" do
      {_pid, name} = start_buffer(cap: 100)

      for i <- 1..100 do
        Buffer.append(build_entry(id: i), name)
      end

      assert length(Buffer.read(Filter.all(), 1_000, name)) == 100

      Buffer.resize(500, name)

      for i <- 101..300 do
        Buffer.append(build_entry(id: i), name)
      end

      assert length(Buffer.read(Filter.all(), 1_000, name)) == 300
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
    # Appends broadcast as ~100ms batches, not per line — a navigation's
    # burst of SQL/debug lines was pushing one WS frame + one hidden-drawer
    # DOM insert per log line to every connected page while that same
    # navigation was in flight (campaigns/instant-navigation.md Phase 5).

    test "batches appended entries into one {:log_entries, entries} broadcast" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      first_entry = build_entry(message: "pubsub batch one")
      second_entry = build_entry(message: "pubsub batch two")
      Buffer.append(first_entry, name)
      Buffer.append(second_entry, name)

      # Force the batch out deterministically. `append` is a cast and `flush`
      # is a call from this same process, so message ordering guarantees both
      # appends are processed before the flush — no racing the ~100ms flush
      # timer against scheduler jitter (the source of a full-suite-load flake).
      :ok = Buffer.flush(name)

      # One flush, chronological order. The refute matches only this
      # buffer's entries: the suite's global Console.Buffer broadcasts on
      # the same topic, so refuting any {:log_entries, _} races every
      # concurrently-logging test in the suite.
      assert_receive {:log_entries, [^first_entry, ^second_entry]}, 500
      refute_receive {:log_entries, [%{message: "pubsub batch" <> _} | _]}, 150
    end

    test "a later append after a flush starts a new batch" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      first_entry = build_entry(message: "batch window one")
      Buffer.append(first_entry, name)
      :ok = Buffer.flush(name)
      assert_receive {:log_entries, [^first_entry]}, 500

      second_entry = build_entry(message: "batch window two")
      Buffer.append(second_entry, name)
      :ok = Buffer.flush(name)
      assert_receive {:log_entries, [^second_entry]}, 500
    end

    test "clear drops any unflushed batch" do
      {_pid, name} = start_buffer()
      Phoenix.PubSub.subscribe(MediaCentaur.PubSub, Topics.console_logs())

      doomed_entry = build_entry(message: "doomed entry")
      Buffer.append(doomed_entry, name)
      Buffer.clear(name)

      # Only this buffer's entry counts as a leak — the suite's global
      # Console.Buffer broadcasts on the same topic, so refuting any
      # {:log_entries, _} races every concurrently-logging test.
      assert_receive :buffer_cleared, 500
      refute_receive {:log_entries, [^doomed_entry]}, 200
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
      Buffer.config(name)

      # Now verify the settings row exists.
      settings_entry = MediaCentaur.Settings.get_by_key("console_filter")
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

      config = Buffer.config(name)

      # cap defaults to 2_000 (or whatever was persisted; just check it's in range)
      assert config.cap >= 100
      assert config.cap <= 50_000
      assert %Filter{} = config.filter
    end
  end

  describe "append crash-safety" do
    test "append/2 with a non-existent name is a no-op and does not crash" do
      result = Buffer.append(build_entry(), :nonexistent_buffer_name)
      assert result == :ok
    end
  end

  describe "per-component rings" do
    test "a chatty component does not evict a quiet component's entries" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      Buffer.append(build_entry(component: :watcher, message: "watcher line"), name)

      for n <- 1..500 do
        Buffer.append(build_entry(component: :ecto, message: "ecto #{n}"), name)
      end

      :ok = Buffer.flush(name)

      messages = Filter.all() |> Buffer.read(1_000, name) |> Enum.map(& &1.message)

      assert "watcher line" in messages
    end

    test "each component's ring is capped independently" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      for n <- 1..50 do
        Buffer.append(build_entry(component: :watcher, message: "w#{n}"), name)
        Buffer.append(build_entry(component: :pipeline, message: "p#{n}"), name)
      end

      :ok = Buffer.flush(name)

      watcher = Filter.new(components: %{watcher: :show}, default_component: :hide, level: :debug)
      pipeline = Filter.new(components: %{pipeline: :show}, default_component: :hide, level: :debug)

      assert length(Buffer.read(watcher, 1_000, name)) == 10
      assert length(Buffer.read(pipeline, 1_000, name)) == 10
    end

    test "a ring read between trims still yields at most the cap" do
      # Each ring is trimmed once per cap/4 appends, not on every append, so
      # between trims it runs over. 110 appends at cap 100 trims on the 100th
      # and leaves ten un-trimmed — the read must still cap at 100.
      {_pid, name} = start_buffer(cap: 100, persist_debounce_ms: 50_000)

      for n <- 1..110 do
        Buffer.append(build_entry(id: n, component: :watcher, message: "w#{n}"), name)
      end

      :ok = Buffer.flush(name)

      entries = Buffer.read(Filter.all(), 1_000, name)

      assert length(entries) == 100
      # Newest-first, and the over-run is dropped from the tail, not the head.
      assert hd(entries).message == "w110"
      assert List.last(entries).message == "w11"
    end
  end

  describe "read/2" do
    test "returns entries newest-first across rings, ordered by id" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      first = build_entry(component: :watcher, message: "first")
      second = build_entry(component: :pipeline, message: "second")
      third = build_entry(component: :watcher, message: "third")

      for entry <- [first, second, third], do: Buffer.append(entry, name)
      :ok = Buffer.flush(name)

      assert ["third", "second", "first"] =
               Filter.all() |> Buffer.read(10, name) |> Enum.map(& &1.message)
    end

    test "pulls only the rings the filter makes visible" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      Buffer.append(build_entry(component: :watcher, message: "watcher line"), name)
      Buffer.append(build_entry(component: :ecto, message: "ecto line"), name)
      :ok = Buffer.flush(name)

      filter = Filter.new(components: %{watcher: :show}, default_component: :hide, level: :debug)

      assert ["watcher line"] = filter |> Buffer.read(10, name) |> Enum.map(& &1.message)
    end

    test "applies the filter's level floor" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      Buffer.append(build_entry(component: :watcher, level: :debug, message: "noisy"), name)
      Buffer.append(build_entry(component: :watcher, level: :warning, message: "important"), name)
      :ok = Buffer.flush(name)

      filter = Filter.new(level: :info, default_component: :show)

      assert ["important"] = filter |> Buffer.read(10, name) |> Enum.map(& &1.message)
    end

    test "honours the limit" do
      {_pid, name} = start_buffer(cap: 100, persist_debounce_ms: 50_000)

      for n <- 1..20, do: Buffer.append(build_entry(component: :watcher, message: "m#{n}"), name)
      :ok = Buffer.flush(name)

      assert length(Buffer.read(Filter.all(), 5, name)) == 5
    end

    test "folds an unknown component into the :system ring" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      Buffer.append(build_entry(component: :not_a_real_component, message: "stray"), name)
      :ok = Buffer.flush(name)

      system_filter =
        Filter.new(components: %{system: :show}, default_component: :hide, level: :debug)

      assert ["stray"] = system_filter |> Buffer.read(10, name) |> Enum.map(& &1.message)
    end
  end

  describe "config/0" do
    test "reports the current cap and filter" do
      {_pid, name} = start_buffer(cap: 10, persist_debounce_ms: 50_000)

      filter = Filter.new(level: :warning, default_component: :show)
      :ok = Buffer.put_filter(filter, name)

      config = Buffer.config(name)

      assert config.cap == 10
      assert config.filter.level == :warning
    end
  end
end
