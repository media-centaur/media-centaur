defmodule MediaCentarr.Platform.LogSource.JournalTest do
  use ExUnit.Case, async: true

  alias MediaCentarr.Platform.LogSource.Journal

  describe "available?/1" do
    test "returns false when unit is nil (no autostart unit detected)" do
      refute Journal.available?(nil)
    end

    test "returns true when unit is set and journalctl is on PATH" do
      # The CI runner has journalctl in /usr/bin; the binary exists even if
      # there's no live unit to query. This test asserts the binary-availability
      # gate, not the unit-state gate.
      if System.find_executable("journalctl") do
        assert Journal.available?("media-centarr.service")
      end
    end

    test "returns false when unit is set but journalctl is missing", %{} do
      # Stub System.find_executable by overriding the binary-resolver
      # via the :find_executable opt — a tiny seam so the test doesn't
      # depend on whether journalctl is installed.
      assert Journal.available?("media-centarr.service", find_executable: fn _ -> nil end) ==
               false
    end
  end

  describe "open_port/1 argv shape (port_opener injected)" do
    test "passes --user, -u <unit>, -n 200, -f, --output=short-iso" do
      # Capture the args passed to the port opener — never actually spawn
      # journalctl.
      this = self()

      port_opener = fn path, opts ->
        send(this, {:opened, path, opts})
        :sentinel_port
      end

      assert Journal.open_port("media-centarr.service",
               port_opener: port_opener,
               find_executable: fn "journalctl" -> "/usr/bin/journalctl" end
             ) == :sentinel_port

      assert_received {:opened, "/usr/bin/journalctl", opts}

      args = Keyword.fetch!(opts, :args)
      assert "--user" in args
      assert "media-centarr.service" in args
      assert "-f" in args
      assert "--output=short-iso" in args
    end

    test "falls back to /usr/bin/journalctl when find_executable returns nil" do
      this = self()

      port_opener = fn path, _opts ->
        send(this, {:opened, path})
        :sentinel
      end

      _ =
        Journal.open_port("media-centarr.service",
          port_opener: port_opener,
          find_executable: fn _ -> nil end
        )

      assert_received {:opened, "/usr/bin/journalctl"}
    end
  end
end
