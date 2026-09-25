defmodule MediaCentaur.Playback.BundledScriptsTest do
  @moduledoc """
  Loads the bundled mpv package (`priv/mpv/scripts/media-centaur/`) in a
  real, headless mpv and reads its log. A Lua syntax or runtime error in any
  module fails the load line; the chaptered walk proves the three features
  still fire in order.

  The fixture `chaptered.mkv` (120 s, black 32x32 at 2 fps, chapters Intro
  0–10 s / Body / Credits 96–120 s) was generated once with:

      ffmpeg -i chaptered.ffmeta -f lavfi -i color=c=black:s=32x32:r=2 -t 120 \\
        -map 1:v -map_metadata 0 -c:v libx264 -preset veryfast -pix_fmt yuv420p \\
        -f matroska chaptered.mkv

  mpv is a hard dependency of the app; a machine without it fails these
  tests rather than skipping them.
  """

  use MediaCentaur.Case, async: true

  @fixtures Path.expand("../../support/fixtures/mpv", __DIR__)
  @fixture Path.join(@fixtures, "chaptered.mkv")
  @driver Path.join(@fixtures, "driver.lua")

  @moduletag :tmp_dir

  describe "loading" do
    test "every feature registers and the package reports loaded", %{tmp_dir: home} do
      {status, output} = run_mpv(["--frames=1", @fixture], home)

      assert status == 0, output
      assert output =~ "[media_centaur] loaded: skip_intro=true next_episode=true track_menu=true"
      assert output =~ "skip-intro: chapter observer registered"
      assert output =~ "next-episode: chapter + playlist + time-remaining observers registered"
      assert output =~ "track-menu: bindings registered"
      refute output =~ ~r/error|traceback/i
    end

    test "a script option turns a feature off", %{tmp_dir: home} do
      {status, output} =
        run_mpv(["--frames=1", "--script-opts=media_centaur-skip_intro=no", @fixture], home)

      assert status == 0, output
      assert output =~ "[media_centaur] loaded: skip_intro=false next_episode=true track_menu=true"
      refute output =~ "skip-intro:"
      refute output =~ ~r/error|traceback/i
    end
  end

  describe "chaptered playback" do
    test "Skip Intro, Next Episode, the countdown and the advance fire in order", %{tmp_dir: home} do
      args = [
        "--script=#{@driver}",
        "--msg-level=all=error,media_centaur=debug,driver=info",
        @fixture,
        @fixture
      ]

      {status, output} = run_mpv(args, home, 15_000)

      assert status == 0, output
      refute output =~ ~r/error|traceback/i

      assert_in_order(output, [
        "skip-intro: show: skip target=10s",
        "skip-intro: pill shown",
        "[driver] step: ENTER on Skip Intro",
        "skip-intro: skip: seeking to 10s",
        "skip-intro: hide: fading out",
        "[driver] step: seek to credits",
        "next-episode: is_credits: matched 'Credits'",
        "next-episode: pill shown",
        "[driver] step: seek into the countdown window",
        "next-episode: set_mode: skip → countdown",
        "[driver] step: ENTER on Next Episode",
        "next-episode: advance: playlist-next",
        "next-episode: cleanup_overlay",
        "[driver] file-loaded #2 playlist-pos=1"
      ])
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  # Every line must appear, each after the previous one.
  defp assert_in_order(output, expected_lines) do
    Enum.reduce(expected_lines, 0, fn line, offset ->
      rest = binary_part(output, offset, byte_size(output) - offset)

      case :binary.match(rest, line) do
        {position, length} ->
          offset + position + length

        :nomatch ->
          flunk("expected #{inspect(line)} after byte #{offset} of mpv's output:\n#{output}")
      end
    end)
  end

  # Runs headless mpv with the bundled package and returns {exit_status, output}.
  # HOME points at the test's tmp dir so the track menu's per-folder sound
  # memory never touches the real ~/.local/state. A run past the deadline is
  # killed and fails; it never hangs the suite.
  defp run_mpv(extra_args, home, timeout_ms \\ 10_000) do
    mpv = System.find_executable("mpv")
    assert mpv, "mpv is not on PATH; it is a hard dependency of the app and of this test"

    package = Application.app_dir(:media_centaur, "priv/mpv/scripts/media-centaur")

    args =
      [
        "--no-config",
        "--vo=null",
        "--ao=null",
        "--script=#{package}",
        "--msg-level=all=error,media_centaur=info"
      ] ++ extra_args

    port =
      Port.open({:spawn_executable, mpv}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:env, [{~c"HOME", String.to_charlist(home)}]},
        args: args
      ])

    collect(port, [], System.monotonic_time(:millisecond) + timeout_ms, timeout_ms)
  end

  defp collect(port, chunks, deadline, timeout_ms) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, chunk}} ->
        collect(port, [chunks, chunk], deadline, timeout_ms)

      {^port, {:exit_status, status}} ->
        {status, IO.iodata_to_binary(chunks)}
    after
      remaining ->
        kill(port)
        flunk("mpv did not exit within #{timeout_ms} ms; output so far:\n#{IO.iodata_to_binary(chunks)}")
    end
  end

  defp kill(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} -> System.cmd("kill", ["-9", Integer.to_string(os_pid)], env: [])
      nil -> :ok
    end
  end
end
