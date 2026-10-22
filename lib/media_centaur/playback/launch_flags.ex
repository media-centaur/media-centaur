defmodule MediaCentaur.Playback.LaunchFlags do
  @moduledoc """
  The mpv options one playback session needs, as `{option, value}` pairs,
  and the command line a spawned mpv gets from them.

  Three kinds, because two transports render them differently
  (`Playback.Transport`):

    * **Process options** (`process_options/1`) — what only a process the
      host spawns needs: the window, the quiet terminal, the IPC socket,
      the log file, the bundled scripts path. A remote player owns these
      itself.
    * **Session options** (`session_options/1`) — what every mpv playing
      a session needs, spawned or remote: the behaviours the observer
      depends on, the language policy, the profile. `Transport.Local`
      renders them into the argv; `Transport.Remote` sends each as an IPC
      `set_property` (`script-opts-append` as `change-list`).
    * **The file target** (`launch_target/2`) — the file and its resume
      position, scoped to that file.

  Rule: **the session never depends on anything in the user's mpv config.**
  mpv gives command-line options precedence over every config file, so
  each behaviour `MpvSession` relies on is pinned here and survives
  whatever `~/.config/mpv/mpv.conf` says. The user config itself stays
  untouched and fully live: no `config-dir`, no `no-config`, no
  `load-scripts=no`, so the user's own `mpv.conf`, `input.conf`, scripts
  and script options apply on every app launch exactly as they do when
  mpv is started by hand.

  Why each pinned option exists:

    * `keep-open=yes` — the session's `eof-reached` handling (and the
      moduledoc claim that quit-on-EOF only fires at true playlist end)
      holds for `yes` and `no`; `always` fires `eof-reached` at every file
      and would quit mpv mid-chain.
    * `resume-playback=no` — the app owns position (`start`), track
      choice (`alang`/`slang`, remembered tracks) and the sound toggles.
      mpv's watch-later restore fills in `start`, `aid`, `sid`, `af` and
      more for any option the command line did not set, which is exactly
      the app's restart-from-0 launch (no `start`). Verified 2026-09-25
      with mpv 0.41.
    * `script=<bundled scripts>` — the couch behaviours (Skip Intro, Next
      Episode, the track menu) ship inside the release as one mpv
      directory script and load per launch, never copied into the user
      config. See `docs/mpv.md`. A remote player ships the same package
      in its own assets.
    * `script-opts-append=media_centaur_session-profile_id=<id>` — the
      profile the session records under (ADR-078) lives in the mpv
      process, the one thing that survives a backend restart;
      `SessionRecovery` reads it back over IPC. `-append`, never
      `script-opts=`, so the user's own script options in `mpv.conf` stay
      as they are. The identifier `media_centaur_session` is not the
      bundled script's `media_centaur`, so `mp.options.read_options` in
      `priv/mpv/scripts/media-centaur/main.lua` never sees an unknown key.
  """

  @app :media_centaur
  @bundled_scripts_path "priv/mpv/scripts/media-centaur"
  @profile_script_opt "media_centaur_session-profile_id"

  @typedoc "One mpv option and its value, as `--option=value` would spell it."
  @type option :: {String.t(), String.t()}

  @typedoc "What one launch needs from the session."
  @type input :: %{
          socket_path: String.t(),
          log_file_path: String.t(),
          language_options: [option()],
          content_url: String.t(),
          start_position: number(),
          bundled_scripts_dir: Path.t(),
          profile_id: String.t()
        }

  @doc "The options only a spawned mpv process needs."
  @spec process_options(%{
          socket_path: String.t(),
          log_file_path: String.t(),
          bundled_scripts_dir: Path.t()
        }) :: [option()]
  def process_options(input) do
    [
      {"fullscreen", "yes"},
      {"terminal", "no"},
      {"msg-level", "all=error"},
      {"force-window", "immediate"},
      {"input-ipc-server", input.socket_path},
      {"log-file", input.log_file_path},
      {"script", input.bundled_scripts_dir}
    ]
  end

  @doc "The options every mpv playing this session needs, whichever machine runs it."
  @spec session_options(%{profile_id: String.t(), language_options: [option()]}) :: [option()]
  def session_options(input) do
    [
      {"keep-open", "yes"},
      {"resume-playback", "no"},
      {"script-opts-append", "#{@profile_script_opt}=#{input.profile_id}"}
    ] ++ input.language_options
  end

  @doc "The full argv for a spawned mpv: every option as `--name=value`, ending with the launch target."
  @spec argv(input()) :: [String.t()]
  def argv(input) do
    Enum.map(process_options(input) ++ session_options(input), fn {name, value} ->
      "--#{name}=#{value}"
    end) ++
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

  @doc "The script option key that carries the session's profile id, as mpv reports it in `script-opts`."
  @spec profile_script_opt() :: String.t()
  def profile_script_opt, do: @profile_script_opt

  @doc "The bundled scripts package inside this release (or the dev checkout's `priv/`)."
  @spec bundled_scripts_dir() :: Path.t()
  def bundled_scripts_dir, do: Application.app_dir(@app, @bundled_scripts_path)
end
