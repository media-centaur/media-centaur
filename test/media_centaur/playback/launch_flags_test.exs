defmodule MediaCentaur.Playback.LaunchFlagsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.LaunchFlags

  defp input(overrides \\ %{}) do
    Map.merge(
      %{
        socket_path: "/tmp/media-centaur-entity.sock",
        log_file_path: "/tmp/media-centaur-abcd.log",
        language_flags: ["--alang=jpn,eng", "--slang=eng"],
        content_url: "/media/a.mkv",
        start_position: 0,
        bundled_scripts_dir: "/opt/media-centaur/priv/mpv/scripts/media-centaur"
      },
      overrides
    )
  end

  describe "build/1 — every session assumption is a launch flag" do
    test "pins the flags the IPC session depends on, independent of the user's mpv.conf" do
      flags = LaunchFlags.build(input())

      assert "--keep-open=yes" in flags
      assert "--resume-playback=no" in flags
      assert "--input-ipc-server=/tmp/media-centaur-entity.sock" in flags
      assert "--log-file=/tmp/media-centaur-abcd.log" in flags
      assert "--fullscreen" in flags
      assert "--no-terminal" in flags
      assert "--force-window=immediate" in flags
    end

    test "loads the bundled scripts package on every launch" do
      assert "--script=/opt/media-centaur/priv/mpv/scripts/media-centaur" in LaunchFlags.build(input())
    end

    test "never takes over the user config: no --config-dir, --no-config or --load-scripts" do
      flags = LaunchFlags.build(input())

      refute Enum.any?(flags, &String.starts_with?(&1, "--config-dir"))
      refute Enum.any?(flags, &String.starts_with?(&1, "--no-config"))
      refute Enum.any?(flags, &String.starts_with?(&1, "--load-scripts"))
    end

    test "language flags precede the launch target, which is the tail" do
      flags = LaunchFlags.build(input(%{start_position: 90}))

      assert Enum.take(flags, -4) == ["--{", "--start=90", "/media/a.mkv", "--}"]
      alang_index = Enum.find_index(flags, &(&1 == "--alang=jpn,eng"))
      assert alang_index < Enum.find_index(flags, &(&1 == "--{"))
    end
  end

  describe "launch_target/2" do
    test "scopes the resume position to the first file via per-file option grouping" do
      assert LaunchFlags.launch_target("/media/a.mkv", 1200.5) ==
               ["--{", "--start=1200.5", "/media/a.mkv", "--}"]
    end

    test "no resume position yields the bare path with no start flag" do
      assert LaunchFlags.launch_target("/media/a.mkv", 0) == ["/media/a.mkv"]
    end

    # Regression pin for the ADR-062 leak: a bare global --start applies to
    # every playlist entry mpv loads, so an unwatched appended successor
    # would begin at the first episode's resume offset. The flag must only
    # ever appear inside a --{ … --} group.
    test "a resume position never produces a bare global --start" do
      flags = LaunchFlags.launch_target("/media/a.mkv", 300)
      start_index = Enum.find_index(flags, &String.starts_with?(&1, "--start="))
      assert Enum.at(flags, start_index - 1) == "--{"
      assert List.last(flags) == "--}"
    end
  end

  describe "bundled_scripts_dir/0" do
    test "resolves to the shipped package, which has a main.lua for mpv to load" do
      dir = LaunchFlags.bundled_scripts_dir()

      assert String.ends_with?(dir, "priv/mpv/scripts/media-centaur")
      assert File.regular?(Path.join(dir, "main.lua"))
    end
  end
end
