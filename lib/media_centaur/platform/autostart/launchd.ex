defmodule MediaCentaur.Platform.Autostart.Launchd do
  @moduledoc """
  macOS implementation of `MediaCentaur.Platform.Autostart`.

  Wraps `launchctl` for the LaunchAgent that supervises the running
  media-centaur release. The agent's plist (which the macOS
  installer drops into `~/Library/LaunchAgents/`) sets the Label to
  `com.media-centaur.app` — that's the identifier every `launchctl`
  call here targets.

  ## launchctl semantics

  All control commands address the agent in the
  `gui/<uid>` domain — the per-user GUI session where LaunchAgents
  live. `<uid>` is read from `id -u` at call time.

  * **Restart**: `launchctl kickstart -k gui/<uid>/<label>` — `-k`
    sends SIGTERM, waits for exit, then restarts the agent. Single
    command, no caller deadlock because the new agent instance is
    spawned independently. The Linux analog is
    `systemctl --user restart --no-block`.
  * **Stop**: `launchctl bootout gui/<uid> <label>` — fully unloads
    the agent.
  * **State**: `launchctl print gui/<uid>/<label>` — exits 0 if
    the label is loaded into the GUI domain, non-zero otherwise.

  ## under_launchd detection

  Launchd doesn't set a single canonical env var the way systemd's
  `INVOCATION_ID` does. The closest signal is `LAUNCHD_SOCKET` (set
  per-session by launchd itself) — its presence indicates we're
  inside a launchd-supervised session.
  """

  @behaviour MediaCentaur.Platform.Autostart

  require MediaCentaur.Log, as: Log

  @default_label "com.media-centaur.app"
  @handoff_env_vars []
  @tarball_required_paths ["share/launchd/com.media-centaur.app.plist"]

  @impl MediaCentaur.Platform.Autostart
  def handoff_env_vars, do: @handoff_env_vars

  @impl MediaCentaur.Platform.Autostart
  def tarball_required_paths, do: @tarball_required_paths

  @impl MediaCentaur.Platform.Autostart
  def state(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    env_fn = Keyword.get(opts, :env_fn, &System.get_env/1)
    label = Keyword.get(opts, :label, @default_label)

    under = under_launchd?(env_fn)
    available = under
    installed_active = available and label_loaded?(cmd_fn, label)

    %{
      under_supervisor: under,
      unit_name: label,
      supervisor_available: available,
      unit_installed: installed_active,
      active: installed_active,
      enabled: installed_active
    }
  end

  @impl MediaCentaur.Platform.Autostart
  def detected_unit(opts \\ []) do
    env_fn = Keyword.get(opts, :env_fn, &System.get_env/1)
    if under_launchd?(env_fn), do: Keyword.get(opts, :label, @default_label)
  end

  @impl MediaCentaur.Platform.Autostart
  def restart(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    label = Keyword.get(opts, :label, @default_label)
    target = "gui/#{user_uid(cmd_fn)}/#{label}"
    Log.info(:system, "restarting #{label} via launchctl kickstart -k")

    case cmd_fn.("launchctl", ["kickstart", "-k", target]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:launchctl_failed, code, String.trim(output)}}
    end
  end

  @impl MediaCentaur.Platform.Autostart
  def stop(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    label = Keyword.get(opts, :label, @default_label)
    domain = "gui/#{user_uid(cmd_fn)}"
    Log.info(:system, "stopping #{label} via launchctl bootout")

    case cmd_fn.("launchctl", ["bootout", domain, label]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:launchctl_failed, code, String.trim(output)}}
    end
  end

  @impl MediaCentaur.Platform.Autostart
  def status_output(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    label = Keyword.get(opts, :label, @default_label)
    target = "gui/#{user_uid(cmd_fn)}/#{label}"

    try do
      {output, _code} = cmd_fn.("launchctl", ["print", target])
      {:ok, output}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  # --- Private ---

  defp under_launchd?(env_fn) do
    case env_fn.("LAUNCHD_SOCKET") do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp label_loaded?(cmd_fn, label) do
    target = "gui/#{user_uid(cmd_fn)}/#{label}"

    case cmd_fn.("launchctl", ["print", target]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  defp user_uid(cmd_fn) do
    case cmd_fn.("id", ["-u"]) do
      {output, 0} -> String.trim(output)
      _ -> "0"
    end
  end

  # Mirror Systemd.default_cmd's env redaction: launchctl doesn't
  # need any inherited env vars (handoff_env_vars/0 returns []), so
  # we pass only redacted secrets. Elixir 1.19's System.cmd requires
  # env values to be binaries; blank `""` keeps the var defined but
  # empty.
  @redact_env_vars [
    "SECRET_KEY_BASE",
    "TMDB_API_KEY",
    "PROWLARR_API_KEY",
    "DOWNLOAD_CLIENT_PASSWORD"
  ]

  defp default_cmd(binary, args) do
    resolved = System.find_executable(binary) || binary
    redacted = Enum.map(@redact_env_vars, &{&1, ""})
    System.cmd(resolved, args, stderr_to_stdout: true, env: redacted)
  rescue
    ErlangError -> {"", 127}
  end
end
