defmodule MediaCentaur.Console.EntryTest do
  use ExUnit.Case, async: true

  alias MediaCentaur.Console.Entry

  describe "new/1" do
    test "creates a struct when all required keys are provided" do
      timestamp = DateTime.utc_now()

      entry =
        Entry.new(
          id: 1,
          timestamp: timestamp,
          level: :info,
          component: :pipeline,
          message: "hello"
        )

      assert entry.id == 1
      assert entry.timestamp == timestamp
      assert entry.level == :info
      assert entry.component == :pipeline
      assert entry.message == "hello"
    end

    test "defaults metadata to empty map when not provided" do
      entry =
        Entry.new(
          id: 2,
          timestamp: DateTime.utc_now(),
          level: :debug,
          component: :watcher,
          message: "watching"
        )

      assert entry.metadata == %{}
    end

    test "defaults module to nil when not provided" do
      entry =
        Entry.new(
          id: 3,
          timestamp: DateTime.utc_now(),
          level: :error,
          component: :tmdb,
          message: "failed"
        )

      assert entry.module == nil
    end

    test "accepts explicit metadata and module values" do
      entry =
        Entry.new(
          id: 4,
          timestamp: DateTime.utc_now(),
          level: :warning,
          component: :library,
          message: "something",
          module: SomeModule,
          metadata: %{key: "value"}
        )

      assert entry.module == SomeModule
      assert entry.metadata == %{key: "value"}
    end

    test "raises KeyError when id is missing" do
      assert_raise KeyError, fn ->
        Entry.new(
          timestamp: DateTime.utc_now(),
          level: :info,
          component: :pipeline,
          message: "missing id"
        )
      end
    end

    test "raises KeyError when timestamp is missing" do
      assert_raise KeyError, fn ->
        Entry.new(
          id: 5,
          level: :info,
          component: :pipeline,
          message: "missing timestamp"
        )
      end
    end

    test "raises KeyError when level is missing" do
      assert_raise KeyError, fn ->
        Entry.new(
          id: 6,
          timestamp: DateTime.utc_now(),
          component: :pipeline,
          message: "missing level"
        )
      end
    end

    test "raises KeyError when component is missing" do
      assert_raise KeyError, fn ->
        Entry.new(
          id: 7,
          timestamp: DateTime.utc_now(),
          level: :info,
          message: "missing component"
        )
      end
    end

    test "raises KeyError when message is missing" do
      assert_raise KeyError, fn ->
        Entry.new(
          id: 8,
          timestamp: DateTime.utc_now(),
          level: :info,
          component: :pipeline
        )
      end
    end
  end

  describe "from_log_event/3 — structured OTP reports" do
    test "renders gen_server terminate reports through the stock translator, not inspect" do
      # The flat shape OTP actually logs: label is a sibling of the
      # crash fields, not a wrapper around them.
      report = %{
        label: {:gen_server, :terminate},
        name: MediaCentaur.SampleServer,
        reason:
          {%RuntimeError{message: "boom"},
           [{MediaCentaur.SampleServer, :handle_info, 2, [file: ~c"lib/sample.ex", line: 10]}]},
        last_message: :tick,
        state: %{},
        client_info: nil
      }

      entry = Entry.from_log_event(:error, {:report, report}, %{})

      assert entry.message =~ "GenServer MediaCentaur.SampleServer terminating"
      assert entry.message =~ "(RuntimeError) boom"
      refute entry.message =~ "%{label:"
    end

    test "falls back to inspect for reports no translator understands" do
      entry = Entry.from_log_event(:error, {:report, %{custom: "shape"}}, %{})

      assert entry.message =~ "custom"
    end
  end
end
