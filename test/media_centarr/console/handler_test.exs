defmodule MediaCentarr.Console.HandlerTest do
  use ExUnit.Case, async: false

  alias MediaCentarr.Console.Handler

  # Build a minimal meta map as :logger would provide.
  defp build_meta(opts \\ []) do
    base = %{
      time: :erlang.system_time(:microsecond),
      gl: self(),
      domain: [:elixir]
    }

    Enum.into(opts, base)
  end

  describe "build_entry/3 — component classification" do
    test "explicit :component atom in meta is preserved" do
      meta = build_meta(component: :pipeline)
      entry = Handler.build_entry(:info, {:string, "hello"}, meta)

      assert entry.component == :pipeline
    end

    test "Phoenix.* mfa module classifies as :phoenix" do
      meta = build_meta(mfa: {Phoenix.Endpoint, :call, 2})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :phoenix
    end

    test "Phoenix.LiveView.* mfa module classifies as :live_view (not :phoenix)" do
      meta = build_meta(mfa: {Phoenix.LiveView.Channel, :handle_in, 3})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :live_view
    end

    test "Ecto.* mfa module classifies as :ecto" do
      meta = build_meta(mfa: {Ecto.Repo, :one, 2})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :ecto
    end

    test "Postgrex.* mfa module classifies as :ecto" do
      meta = build_meta(mfa: {Postgrex.Protocol, :handle_cast, 3})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :ecto
    end

    test "DBConnection.* mfa module classifies as :ecto" do
      meta = build_meta(mfa: {DBConnection.Connection, :connect, 2})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :ecto
    end

    test "unknown module classifies as :system" do
      meta = build_meta(mfa: {SomeDeeplyUnknown.Module, :do_thing, 1})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :system
    end

    test "no mfa and no component classifies as :system" do
      meta = build_meta()
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.component == :system
    end
  end

  describe "build_entry/3 — level normalization" do
    test ":notice normalizes to :info" do
      meta = build_meta()
      entry = Handler.build_entry(:notice, {:string, "msg"}, meta)

      assert entry.level == :info
    end

    test ":critical normalizes to :error" do
      meta = build_meta()
      entry = Handler.build_entry(:critical, {:string, "msg"}, meta)

      assert entry.level == :error
    end

    test ":alert normalizes to :error" do
      meta = build_meta()
      entry = Handler.build_entry(:alert, {:string, "msg"}, meta)

      assert entry.level == :error
    end

    test ":emergency normalizes to :error" do
      meta = build_meta()
      entry = Handler.build_entry(:emergency, {:string, "msg"}, meta)

      assert entry.level == :error
    end

    test ":warning passes through as :warning" do
      meta = build_meta()
      entry = Handler.build_entry(:warning, {:string, "msg"}, meta)

      assert entry.level == :warning
    end

    test ":debug passes through as :debug" do
      meta = build_meta()
      entry = Handler.build_entry(:debug, {:string, "msg"}, meta)

      assert entry.level == :debug
    end
  end

  describe "build_entry/3 — metadata pruning" do
    test "pids and refs in meta are dropped (not in allowlist)" do
      meta = build_meta(some_pid: self(), some_ref: make_ref(), extra_key: "should be dropped")
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      refute Map.has_key?(entry.metadata, :some_pid)
      refute Map.has_key?(entry.metadata, :some_ref)
      refute Map.has_key?(entry.metadata, :extra_key)
    end

    test "unknown meta keys are dropped" do
      meta = build_meta(totally_unknown_key: "value", another_unknown: 42)
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      refute Map.has_key?(entry.metadata, :totally_unknown_key)
      refute Map.has_key?(entry.metadata, :another_unknown)
    end

    test ":mfa in meta becomes a formatted string" do
      meta = build_meta(mfa: {Foo.Bar, :baz, 1})
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert is_binary(entry.metadata[:mfa])
      assert entry.metadata[:mfa] =~ "baz/1"
    end

    test ":line integer is kept as-is" do
      meta = build_meta(line: 42)
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.metadata[:line] == 42
    end

    test ":file binary is kept as-is" do
      meta = build_meta(file: "lib/foo.ex")
      entry = Handler.build_entry(:info, {:string, "msg"}, meta)

      assert entry.metadata[:file] == "lib/foo.ex"
    end
  end

  describe "build_entry/3 — message truncation" do
    test "message longer than 2000 bytes is truncated with '...' suffix" do
      long_message = String.duplicate("x", 2_100)
      meta = build_meta()
      entry = Handler.build_entry(:info, {:string, long_message}, meta)

      assert byte_size(entry.message) < byte_size(long_message)
      assert String.ends_with?(entry.message, "...")
    end

    test "message exactly at limit is not truncated" do
      exact_message = String.duplicate("x", 2_000)
      meta = build_meta()
      entry = Handler.build_entry(:info, {:string, exact_message}, meta)

      refute String.ends_with?(entry.message, "...")
      assert byte_size(entry.message) == 2_000
    end
  end

  describe "render_message/1 via build_entry" do
    test "handles {:string, iodata} form" do
      meta = build_meta()
      entry = Handler.build_entry(:info, {:string, ["hello ", "world"]}, meta)

      assert entry.message == "hello world"
    end

    test "handles {:report, map} form" do
      meta = build_meta()
      entry = Handler.build_entry(:info, {:report, %{key: "value"}}, meta)

      assert is_binary(entry.message)
      assert String.length(entry.message) > 0
    end

    test "handles {format, args} charlist format form" do
      meta = build_meta()
      entry = Handler.build_entry(:info, {~c"hello ~s", ["world"]}, meta)

      assert entry.message == "hello world"
    end

    test "strips ANSI escape sequences from {:string, ...} messages" do
      meta = build_meta()
      # Simulate Ecto's pre-colorized output: reset, dim, reset
      ansi_message = "\e[0mQUERY OK \e[90msource=\"settings\"\e[0m"
      entry = Handler.build_entry(:info, {:string, ansi_message}, meta)

      assert entry.message == "QUERY OK source=\"settings\""
      refute String.contains?(entry.message, "\e[")
      refute String.contains?(entry.message, "[0m")
      refute String.contains?(entry.message, "[90m")
    end

    test "strips ANSI escape sequences from {format, args} messages" do
      meta = build_meta()
      # Charlist format that includes ANSI codes
      entry =
        Handler.build_entry(
          :info,
          {~c"\e[32m~s\e[0m done", ["work"]},
          meta
        )

      assert entry.message == "work done"
    end
  end

  describe "log/2 reentrancy guard" do
    test "entry with mc_log_source: :buffer is ignored" do
      # Buffer is started by the application supervision tree — it is already running.
      # Subscribe to observe any appends.
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.console_logs())

      meta = build_meta(mc_log_source: :buffer)
      event = %{level: :info, msg: {:string, "should be skipped"}, meta: meta}
      Handler.log(event, %{})

      # No {:log_entry, _} should arrive.
      refute_receive {:log_entry, _}, 100
    end
  end

  describe "integration: full log path" do
    setup do
      # Buffer is started by the application supervision tree — it is already running.
      # The application also installs :media_centarr_console, so add a separate test
      # handler to avoid interfering with the application handler.
      handler_id = :console_test_handler

      :logger.add_handler(handler_id, MediaCentarr.Console.Handler, %{})

      on_exit(fn ->
        :logger.remove_handler(handler_id)
      end)

      {:ok, handler_id: handler_id}
    end

    test "Logger.warning funnels through handler into buffer" do
      Phoenix.PubSub.subscribe(MediaCentarr.PubSub, MediaCentarr.Topics.console_logs())

      # Use :warning since test config sets the global logger level to :warning,
      # which means :info messages are filtered before reaching any handler.
      require Logger
      Logger.warning("integration test message", component: :pipeline)

      assert_receive {:log_entry, entry}, 1_000
      assert entry.component == :pipeline
      assert entry.message =~ "integration test message"
    end
  end
end
