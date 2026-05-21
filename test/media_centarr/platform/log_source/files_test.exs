defmodule MediaCentarr.Platform.LogSource.FilesTest do
  use ExUnit.Case, async: true

  @moduletag :tmp_dir

  alias MediaCentarr.Platform.LogSource.Files

  describe "available?/2" do
    test "returns true when at least one of the configured paths exists", %{tmp_dir: tmp_dir} do
      stdout = Path.join(tmp_dir, "stdout.log")
      stderr = Path.join(tmp_dir, "stderr.log")
      File.write!(stdout, "first line\n")

      # `unit` is the launchd Label — accepted but unused on macOS.
      assert Files.available?("com.media-centarr.app", paths: [stdout, stderr])
    end

    test "returns false when none of the configured paths exist", %{tmp_dir: tmp_dir} do
      missing = Path.join(tmp_dir, "no-such.log")
      refute Files.available?("com.media-centarr.app", paths: [missing])
    end

    test "returns false when unit is nil (no LaunchAgent detected)" do
      refute Files.available?(nil, paths: ["/tmp/some-fake-path.log"])
    end
  end

  describe "open_port/2" do
    test "spawns `tail -F` against the configured paths (port_opener captured)", %{tmp_dir: tmp_dir} do
      stdout = Path.join(tmp_dir, "stdout.log")
      stderr = Path.join(tmp_dir, "stderr.log")
      File.write!(stdout, "")
      File.write!(stderr, "")

      this = self()

      port_opener = fn path, opts ->
        send(this, {:opened, path, opts})
        :sentinel_port
      end

      assert :sentinel_port =
               Files.open_port("com.media-centarr.app",
                 paths: [stdout, stderr],
                 port_opener: port_opener,
                 find_executable: fn "tail" -> "/usr/bin/tail" end
               )

      assert_received {:opened, "/usr/bin/tail", opts}
      args = Keyword.fetch!(opts, :args)
      assert "-F" in args
      assert stdout in args
      assert stderr in args
    end

    test "falls back to /usr/bin/tail when find_executable returns nil" do
      this = self()

      port_opener = fn path, _opts ->
        send(this, {:opened, path})
        :sentinel
      end

      _ =
        Files.open_port("com.media-centarr.app",
          paths: ["/tmp/x.log"],
          port_opener: port_opener,
          find_executable: fn _ -> nil end
        )

      assert_received {:opened, "/usr/bin/tail"}
    end

    test "uses default log paths when :paths opt is omitted (no actual spawn)" do
      # Sanity check: open_port computes the default paths from $HOME +
      # Library/Logs/<…>. We capture via port_opener; no real subprocess.
      this = self()

      port_opener = fn _path, opts ->
        send(this, {:opened_default_args, opts})
        :sentinel
      end

      _ =
        Files.open_port("com.media-centarr.app",
          port_opener: port_opener,
          find_executable: fn _ -> "/usr/bin/tail" end
        )

      assert_received {:opened_default_args, opts}
      args = Keyword.fetch!(opts, :args)
      assert "-F" in args
      # Default paths target the macOS-conventional location.
      assert Enum.any?(args, &String.contains?(&1, "Library/Logs"))
    end
  end
end
