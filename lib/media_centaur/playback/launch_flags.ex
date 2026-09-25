defmodule MediaCentaur.Playback.LaunchFlags do
  @moduledoc """
  The mpv command line for one playback session.

  Rule: **the session never depends on anything in the user's mpv config.**
  mpv gives command-line options precedence over every config file, so each
  behaviour `MpvSession` relies on is pinned here as a launch flag and
  survives whatever `~/.config/mpv/mpv.conf` says. The user config itself
  stays untouched and fully live: no `--config-dir`, no `--no-config`, no
  `--load-scripts=no`, so the user's own `mpv.conf`, `input.conf`, scripts
  and script options apply on every app launch exactly as they do when mpv
  is started by hand.

  Why each pinned flag exists:

    * `--keep-open=yes` — the session's `eof-reached` handling (and the
      moduledoc claim that quit-on-EOF only fires at true playlist end)
      holds for `yes` and `no`; `always` fires `eof-reached` at every file
      and would quit mpv mid-chain.
    * `--resume-playback=no` — the app owns position (`--start`), track
      choice (`--alang`/`--slang`, remembered tracks) and the sound
      toggles. mpv's watch-later restore fills in `start`, `aid`, `sid`,
      `af` and more for any option the command line did not set, which is
      exactly the app's restart-from-0 launch (no `--start`). Verified
      2026-09-25 with mpv 0.41.
    * `--script=<bundled scripts>` — the couch behaviours (Skip Intro,
      Next Episode, the track menu) ship inside the release as one mpv
      directory script and load per launch, never copied into the user
      config. See `docs/mpv.md`.
  """

  @app :media_centaur
  @bundled_scripts_path "priv/mpv/scripts/media-centaur"

  @typedoc "What one launch needs from the session."
  @type input :: %{
          socket_path: String.t(),
          log_file_path: String.t(),
          language_flags: [String.t()],
          content_url: String.t(),
          start_position: number(),
          bundled_scripts_dir: Path.t()
        }

  @doc "The full argv, ending with the launch target."
  @spec build(input()) :: [String.t()]
  def build(input) do
    [
      "--fullscreen",
      "--no-terminal",
      "--msg-level=all=error",
      "--force-window=immediate",
      "--keep-open=yes",
      "--resume-playback=no",
      "--input-ipc-server=#{input.socket_path}",
      "--log-file=#{input.log_file_path}",
      "--script=#{input.bundled_scripts_dir}"
    ] ++
      input.language_flags ++
      launch_target(input.content_url, input.start_position)
  end

  @doc """
  The argv tail selecting the launch file, with its resume position scoped
  per-file via mpv's `--{ … --}` option grouping.

  A bare global `--start` applies to **every** file mpv loads — including
  successors appended to the playlist (ADR-062) — so an unwatched next
  episode would begin at the first episode's resume offset. The group pins
  the flag to the launch file alone; appended entries carry their own
  per-entry `start` option or none at all (`NextEpisode.loadfile_command/1`).
  """
  @spec launch_target(String.t(), number()) :: [String.t()]
  def launch_target(url, start_position) when start_position > 0 do
    ["--{", "--start=#{start_position}", url, "--}"]
  end

  def launch_target(url, _start_position), do: [url]

  @doc "The bundled scripts package inside this release (or the dev checkout's `priv/`)."
  @spec bundled_scripts_dir() :: Path.t()
  def bundled_scripts_dir, do: Application.app_dir(@app, @bundled_scripts_path)
end
