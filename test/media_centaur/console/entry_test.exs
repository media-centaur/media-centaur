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

  describe "from_log_event/3 — crash-frame component classification" do
    # Crash logs are emitted by the framework (Bandit.Pipeline, proc_lib), so
    # meta[:mfa] alone classifies every crash as :system. The stacktrace in
    # meta[:crash_reason] names the code that actually raised — these tests pin
    # that attribution.

    test "request crash with an app web frame classifies by the owning subsystem" do
      # The shape Bandit logs for a LiveView crash: mfa is Bandit's error
      # handler, the app frame only appears in the crash_reason stacktrace.
      meta = %{
        mfa: {Bandit.Pipeline, :handle_error, 7},
        crash_reason:
          {%KeyError{key: :connectivity, term: %{}},
           [
             {MediaCentaurWeb.IncomingLive, :assign_queue_from_state, 2,
              [file: ~c"lib/media_centaur_web/live/acquisition_live.ex", line: 100]},
             {Phoenix.LiveView.Utils, :call_handle_params!, 5,
              [file: ~c"lib/phoenix_live_view/utils.ex", line: 1]}
           ]}
      }

      entry = Entry.from_log_event(:error, {:string, "** (KeyError) ..."}, meta)

      assert entry.component == :acquisition
    end

    test "crash in a core context module classifies by that context" do
      meta = %{
        mfa: {Bandit.Pipeline, :handle_error, 7},
        crash_reason:
          {%RuntimeError{message: "boom"},
           [
             {MediaCentaur.Downloads.QueueMonitor, :poll, 1,
              [file: ~c"lib/media_centaur/downloads/queue_monitor.ex", line: 10]}
           ]}
      }

      entry = Entry.from_log_event(:error, {:string, "boom"}, meta)

      assert entry.component == :acquisition
    end

    # A crash keeps the emitting context's own component, the same one a
    # deliberate log from that context carries. Folding :nostr onto the
    # friends tile is the board's job (HealthBoard.normalize/1, covered in
    # health_board_test.exs) — doing it here as well used to erase the
    # distinction, so the Console could not filter Nostr crashes at all.
    test "a crash carries its context's component, not the board tile's" do
      for {module, component} <- [
            {MediaCentaur.Nostr.Connection, :nostr},
            {MediaCentaur.Social.Connections.Owner, :social},
            {MediaCentaur.Recommendations.Sync, :social}
          ] do
        meta = %{crash_reason: {%RuntimeError{message: "boom"}, [{module, :handle_info, 2, []}]}}

        assert Entry.from_log_event(:error, {:string, "boom"}, meta).component == component
      end
    end

    test "the first app-owned frame wins over later frames" do
      meta = %{
        crash_reason:
          {%RuntimeError{message: "boom"},
           [
             {Enum, :map, 2, []},
             {MediaCentaur.TMDB.Client, :get, 2, []},
             {MediaCentaur.Library.Movies, :refresh, 1, []}
           ]}
      }

      entry = Entry.from_log_event(:error, {:string, "boom"}, meta)

      assert entry.component == :tmdb
    end

    test "crash with only framework frames stays :system" do
      meta = %{
        mfa: {Bandit.Pipeline, :handle_error, 7},
        crash_reason:
          {%Plug.Conn.WrapperError{},
           [
             {Plug.Conn, :send_resp, 1, []},
             {Bandit.Pipeline, :run, 4, []}
           ]}
      }

      entry = Entry.from_log_event(:error, {:string, "boom"}, meta)

      assert entry.component == :system
    end

    test "explicit :component metadata beats crash-frame classification" do
      meta = %{
        component: :playback,
        crash_reason: {%RuntimeError{message: "boom"}, [{MediaCentaur.Library.Movies, :refresh, 1, []}]}
      }

      entry = Entry.from_log_event(:error, {:string, "boom"}, meta)

      assert entry.component == :playback
    end

    test "gen_server terminate report classifies by the registered name module" do
      report = %{
        label: {:gen_server, :terminate},
        name: MediaCentaur.Acquisition.Reactor,
        reason: {%RuntimeError{message: "boom"}, []},
        last_message: :tick,
        state: %{},
        client_info: nil
      }

      entry = Entry.from_log_event(:error, {:report, report}, %{})

      assert entry.component == :acquisition
    end

    test "gen_server terminate report falls back to crash frames when the name is not app-owned" do
      report = %{
        label: {:gen_server, :terminate},
        name: :some_registered_name,
        reason:
          {%RuntimeError{message: "boom"},
           [{MediaCentaur.Playback.SessionRegistry, :handle_info, 2, []}]},
        last_message: :tick,
        state: %{},
        client_info: nil
      }

      entry = Entry.from_log_event(:error, {:report, report}, %{})

      assert entry.component == :playback
    end
  end
end
