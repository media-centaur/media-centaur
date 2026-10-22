defmodule MediaCentaur.Playback.LaunchFlagsTest do
  use MediaCentaur.Case, async: true

  alias MediaCentaur.Playback.LaunchFlags

  @profile_id "0f1e2d3c-aaaa-bbbb-cccc-123456789abc"

  defp input(overrides \\ %{}) do
    Map.merge(
      %{
        socket_path: "/tmp/media-centaur-entity.sock",
        log_file_path: "/tmp/media-centaur-abcd.log",
        language_options: [{"alang", "jpn,eng"}, {"slang", "eng"}],
        content_url: "/media/a.mkv",
        start_position: 0,
        bundled_scripts_dir: "/opt/media-centaur/priv/mpv/scripts/media-centaur",
        profile_id: @profile_id
      },
      overrides
    )
  end

  describe "process_options/1 — what only a spawned mpv process needs" do
    test "the window, the quiet terminal, the IPC socket, the log file and the bundled scripts" do
      options = LaunchFlags.process_options(input())

      assert {"fullscreen", "yes"} in options
      assert {"terminal", "no"} in options
      assert {"msg-level", "all=error"} in options
      assert {"force-window", "immediate"} in options
      assert {"input-ipc-server", "/tmp/media-centaur-entity.sock"} in options
      assert {"log-file", "/tmp/media-centaur-abcd.log"} in options
      assert {"script", "/opt/media-centaur/priv/mpv/scripts/media-centaur"} in options
    end
  end

  describe "session_options/1 — what every mpv playing a session needs, spawned or remote" do
    test "pins the behaviours the observer depends on, the language policy and the profile" do
      options = LaunchFlags.session_options(input())

      assert {"keep-open", "yes"} in options
      assert {"resume-playback", "no"} in options
      assert {"alang", "jpn,eng"} in options
      assert {"slang", "eng"} in options
      assert {"script-opts-append", "media_centaur_session-profile_id=#{@profile_id}"} in options
    end

    test "carries no process option" do
      names = Enum.map(LaunchFlags.session_options(input()), &elem(&1, 0))
      refute "input-ipc-server" in names
      refute "script" in names
      refute "fullscreen" in names
    end
  end

  describe "argv/1 — the spawned mpv's command line" do
    test "renders every option as --name=value and ends with the launch target" do
      argv = LaunchFlags.argv(input(%{start_position: 90}))

      assert "--keep-open=yes" in argv
      assert "--resume-playback=no" in argv
      assert "--input-ipc-server=/tmp/media-centaur-entity.sock" in argv
      assert "--log-file=/tmp/media-centaur-abcd.log" in argv
      assert "--script=/opt/media-centaur/priv/mpv/scripts/media-centaur" in argv
      assert "--script-opts-append=media_centaur_session-profile_id=#{@profile_id}" in argv
      assert "--fullscreen=yes" in argv
      assert "--terminal=no" in argv
      assert "--force-window=immediate" in argv

      assert Enum.take(argv, -4) == ["--{", "--start=90", "/media/a.mkv", "--}"]
      alang_index = Enum.find_index(argv, &(&1 == "--alang=jpn,eng"))
      assert alang_index < Enum.find_index(argv, &(&1 == "--{"))
    end

    test "never takes over the user config: no --config-dir, --no-config or --load-scripts" do
      argv = LaunchFlags.argv(input())

      refute Enum.any?(argv, &String.starts_with?(&1, "--config-dir"))
      refute Enum.any?(argv, &String.starts_with?(&1, "--no-config"))
      refute Enum.any?(argv, &String.starts_with?(&1, "--load-scripts"))
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
