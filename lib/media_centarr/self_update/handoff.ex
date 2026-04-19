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
      process. `nohup` ignores SIGHUP. Together they ensure the chain
      survives when Erlang closes the Port (which otherwise sends
      SIGPIPE through the inherited stdio pipes).
    * The spawning `Port.open` uses `:nouse_stdio` so Erlang never
      connects its pipes to the child at all. The handoff script
      redirects the installer's own stdout+stderr to a file inside the
      staging dir — the installer's output never flows through the
      broken Erlang stdio path.
    * A `sleep 1` front-matter lets LiveView commit the "Installing and
      restarting…" phase to the browser before the BEAM goes down.

  The `:spawn_fn` option lets tests assert the exact argv shape without
  executing a subprocess. Tests also verify that maliciously-named paths
  can't escape the single argv entry.
  """

  require MediaCentarr.Log, as: Log

  @spec spawn_detached(String.t(), keyword()) :: :ok
  def spawn_detached(staged_root, opts \\ []) do
    spawn_fn = Keyword.get(opts, :spawn_fn, &default_spawn/1)
    home = Keyword.get(opts, :home, System.user_home!())

    installer = Path.join(staged_root, "bin/media-centarr-install")
    log_file = Path.join(staged_root, "handoff.log")

    # The script body is a static string literal. The installer path and
    # log file are passed as positional parameters ($1 and $2) so shell
    # metacharacters in either path are never parsed — they are just
    # argv values to the inner `sh`.
    script = ~s(sleep 1 && exec "$1" >"$2" 2>&1)

    args = [
      "env",
      "-i",
      "HOME=" <> home,
      "PATH=/usr/bin:/bin",
      "setsid",
      "--fork",
      "nohup",
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
    # Critical: without this, `Port.close` below would propagate SIGPIPE
    # through the inherited pipes when the installer tries to write its
    # output, killing the chain before `systemctl restart` runs.
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
