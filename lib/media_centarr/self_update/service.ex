defmodule MediaCentarr.SelfUpdate.Service do
  @moduledoc """
  Systemd-aware controls for the running `media-centarr.service` unit.

  Reads the unit's state (installed / enabled / active) and exposes the
  three user-facing operations the Settings > System page surfaces:
  restart, stop, and a read-only `systemctl status` fetch.

  ## Process model

  Restart and stop use `systemctl --user --no-block …`. The `--no-block`
  flag tells systemd to queue the job and return immediately instead of
  waiting for completion. That matters for restart: without it, the
  `systemctl` process would wait for the unit's ExecStop to finish
  before exiting, but ExecStop kills the very BEAM that spawned
  systemctl — so the caller would deadlock. With --no-block the call
  returns, then systemd kills the BEAM asynchronously, and LiveView
  reconnects to the new BEAM.

  ## Shelling out

  `System.cmd/3` is appropriate here because systemctl itself is quick
  (it's a DBus client, not the thing doing the restart). The heavy
  work happens in systemd after systemctl returns.

  ## Injection

  The `:cmd_fn` option lets tests pass a fake command runner so nothing
  actually fires against the user's real systemd instance during unit
  tests.
  """

  require MediaCentarr.Log, as: Log

  @unit_name "media-centarr.service"

  @type state :: %{
          systemd_available: boolean(),
          unit_installed: boolean(),
          active: boolean(),
          enabled: boolean()
        }

  @doc """
  Returns the current systemd state for the media-centarr user unit.

  Reports `systemd_available: false` on any machine where the user's
  systemd instance can't be reached — that's the app-only install path.
  All other fields are `false` in that case too, so the UI can drive
  off a single `systemd_available` flag.
  """
  @spec state(keyword()) :: state()
  def state(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)

    if systemd_available?(cmd_fn) do
      %{
        systemd_available: true,
        unit_installed: unit_installed?(cmd_fn),
        active: active?(cmd_fn),
        enabled: enabled?(cmd_fn)
      }
    else
      %{systemd_available: false, unit_installed: false, active: false, enabled: false}
    end
  end

  @doc """
  Queues a restart of the unit with `--no-block` so the caller doesn't
  deadlock on its own BEAM being killed. The systemd job completes
  asynchronously after the call returns; LiveView reconnects to the
  new BEAM.
  """
  @spec restart(keyword()) :: :ok | {:error, term()}
  def restart(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    Log.info(:system, "restarting via systemctl --user")

    case cmd_fn.("systemctl", ["--user", "--no-block", "restart", @unit_name]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:systemctl_failed, code, String.trim(output)}}
    end
  end

  @doc """
  Queues a stop of the unit. After this returns, the app will no longer
  be running and the user must run `systemctl --user start
  media-centarr` (or re-enable autostart) to bring it back.
  """
  @spec stop(keyword()) :: :ok | {:error, term()}
  def stop(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    Log.info(:system, "stopping via systemctl --user")

    case cmd_fn.("systemctl", ["--user", "--no-block", "stop", @unit_name]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:systemctl_failed, code, String.trim(output)}}
    end
  end

  @doc """
  Returns the textual output of `systemctl --user status` for the unit.

  systemctl returns a non-zero exit code when the unit is inactive or
  failed; we treat both zero and non-zero exits as success from the
  read's perspective — the output is what the user wants to see either
  way. Only a true error (command not found, etc.) returns an error.
  """
  @spec status_output(keyword()) :: {:ok, String.t()} | {:error, term()}
  def status_output(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)

    try do
      {output, _code} =
        cmd_fn.("systemctl", ["--user", "status", @unit_name, "--no-pager"])

      {:ok, output}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  # --- Internals ---

  defp systemd_available?(cmd_fn) do
    case cmd_fn.("systemctl", ["--user", "show-environment"]) do
      {_output, 0} -> true
      _ -> false
    end
  catch
    _, _ -> false
  end

  defp unit_installed?(cmd_fn) do
    # `list-unit-files` succeeds even for inactive units as long as the
    # file exists on disk.
    case cmd_fn.("systemctl", ["--user", "list-unit-files", @unit_name, "--no-pager"]) do
      {output, 0} -> String.contains?(output, @unit_name)
      _ -> false
    end
  end

  defp active?(cmd_fn) do
    case cmd_fn.("systemctl", ["--user", "is-active", @unit_name]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  defp enabled?(cmd_fn) do
    case cmd_fn.("systemctl", ["--user", "is-enabled", @unit_name]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  # Forward the env vars systemctl needs (XDG_RUNTIME_DIR,
  # DBUS_SESSION_BUS_ADDRESS) while explicitly clearing known secrets
  # out of the child's environment. `System.cmd` merges our env on top
  # of the parent's, so setting a secret to `false` here removes it
  # from the child's view even if it was set in the BEAM.
  defp default_cmd(binary, args) do
    keep =
      Enum.flat_map(["XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"], fn name ->
        case System.get_env(name) do
          nil -> []
          "" -> []
          value -> [{name, value}]
        end
      end)

    # Redact any secrets that might be in the BEAM's env — systemctl
    # doesn't need them, and leaking them into a child process argv
    # or env table is needless exposure.
    redacted =
      Enum.map(
        [
          "SECRET_KEY_BASE",
          "TMDB_API_KEY",
          "PROWLARR_API_KEY",
          "DOWNLOAD_CLIENT_PASSWORD"
        ],
        &{&1, false}
      )

    System.cmd(binary, args, stderr_to_stdout: true, env: keep ++ redacted)
  rescue
    ErlangError -> {"", 127}
  end
end
