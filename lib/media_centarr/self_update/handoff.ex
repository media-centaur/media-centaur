defmodule MediaCentarr.SelfUpdate.Handoff do
  @moduledoc """
  Spawns the staged `bin/media-centarr-install` as a detached process that
  outlives the current BEAM. That detached child runs migrations, flips the
  `current` symlink, and restarts the systemd unit — which kills this BEAM
  and the new release takes over.

  ## Security posture

    * The installer path is passed as a **positional** argv entry (`$1`),
      never interpolated into the `sh -c` command string. A path containing
      `;`, `&&`, `$()`, quotes, or newlines is just a (nonsensical) argv
      value; it is not parsed as shell.
    * The command runs under `env -i` with a minimal `PATH` and only
      `HOME` exported from the current user's environment. Inherited env
      from the web request chain (BEAM session, LiveView socket) cannot
      influence the installer.
    * `setsid --fork` creates a brand-new session with a grandchild
      process. Any SIGHUP from the parent BEAM's restart cannot reach
      the grandchild because it is no longer in the BEAM's session.
    * The spawning `Port.open` uses `:nouse_stdio` so Erlang never
      connects its pipes to the child at all. `Port.close` therefore
      cannot SIGPIPE the chain.
    * The handoff script's first instruction redirects the shell's own
      stdout/stderr to a log file inside the staging dir. Every
      subsequent command — including the `exec`-replaced installer —
      inherits those FDs, so there is one durable diagnostic trail we
      can read back after the update.

  ## Diagnosing a stuck handoff

  If the UI gets stuck on "Restarting the service…" the
  `{staged_root}/handoff.log` file tells you how far the chain got:

    * Missing or empty → the shell never ran (setsid failed, port
      died before exec completed, missing binary, etc.)
    * Contains "handoff: started …" but nothing more → `sleep 1` or
      `exec` failed
    * Contains the installer's banners up to some point → installer
      ran and its output explains where it stopped

  The `:spawn_fn` option lets tests assert the exact argv shape without
  executing a subprocess.
  """

  require MediaCentarr.Log, as: Log

  @spec spawn_detached(String.t(), keyword()) :: :ok
  def spawn_detached(staged_root, opts \\ []) do
    spawn_fn = Keyword.get(opts, :spawn_fn, &default_spawn/1)
    home = Keyword.get(opts, :home, System.user_home!())

    installer = Path.join(staged_root, "bin/media-centarr-install")
    log_file = Path.join(staged_root, "handoff.log")

    # `exec >>"$2" 2>&1` redirects the *shell's own* stdio to the log
    # before any other command runs, so every trace line here — plus
    # the installer's output after `exec "$1"` — lands in the log.
    #
    # `nohup` is intentionally absent. `setsid --fork` already creates
    # a new session, so SIGHUP can't reach the grandchild. Adding
    # `nohup` on top of that would also try to reopen stdio as a side
    # effect, which complicates the redirect we just set up.
    script = ~S"""
    exec >>"$2" 2>&1
    printf 'handoff: started at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    sleep 1
    printf 'handoff: execing %s\n' "$1"
    exec "$1"
    """

    args = [
      "env",
      "-i",
      "HOME=" <> home,
      "PATH=/usr/bin:/bin",
      "setsid",
      "--fork",
      "sh",
      "-c",
      script,
      "--",
      installer,
      log_file
    ]

    Log.info(:system, "handing off to staged installer at #{staged_root}")
    _ = spawn_fn.(args)
    :ok
  end

  defp default_spawn(args) do
    [command | rest] = args

    # `:nouse_stdio` — Erlang does not connect stdin/stdout to the child.
    # Without this, `Port.close` below would propagate SIGPIPE through
    # the inherited pipes when the installer tries to write its output,
    # killing the chain before `systemctl restart` runs. The script
    # redirects its own stdio to the staging-dir log file, so nothing
    # needs to flow through Erlang.
    port =
      Port.open({:spawn_executable, System.find_executable(command)}, [
        :binary,
        :hide,
        :nouse_stdio,
        {:args, rest}
      ])

    true = Port.close(port)
    :ok
  end
end
