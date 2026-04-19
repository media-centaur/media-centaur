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
    * `setsid` + `nohup` detach the child from the controlling terminal
      so the kernel doesn't send SIGHUP when the parent BEAM is restarted
      by systemd during the unit bounce.
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

    args = [
      "env",
      "-i",
      "HOME=" <> home,
      "PATH=/usr/bin:/bin",
      "setsid",
      "nohup",
      "sh",
      "-c",
      "sleep 1 && exec \"$1\"",
      "--",
      installer
    ]

    Log.info(:system, "handing off to staged installer at #{staged_root}")
    _ = spawn_fn.(args)
    :ok
  end

  defp default_spawn(args) do
    [command | rest] = args
    # Keep stdout/stderr untethered from this process — the detached
    # installer manages its own logging into the staging dir.
    port =
      Port.open({:spawn_executable, System.find_executable(command)}, [
        :binary,
        :hide,
        {:args, rest}
      ])

    true = Port.close(port)
    :ok
  end
end
