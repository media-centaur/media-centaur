defmodule MediaCentarr.SelfUpdate.Service do
  @moduledoc """
  Systemd-aware controls for the running media-centarr user unit.

  Two detection signals drive the Settings > System card:

  * **`under_systemd`** — whether this BEAM is actually supervised by systemd.
    Read from the `INVOCATION_ID` env var, which systemd sets for every unit
    execution. Absent ⇒ not under systemd.
  * **`unit_name`** — the specific unit this BEAM belongs to (dev, showcase,
    or prod). Parsed from `/proc/self/cgroup`, whose last `*.service` segment
    is the unit name under both cgroup v2 and v1.

  The older `systemd_available` probe (`systemctl --user show-environment`) is
  kept as a separate axis — it tells us whether we can run `systemctl` at all
  to offer Restart/Stop buttons, independent of whether we're managed.

  ## Process model

  Restart and stop use `systemctl --user --no-block …`. The `--no-block`
  flag queues the job and returns immediately. That matters for restart:
  without it, `systemctl` would wait for ExecStop to finish, but ExecStop
  kills the very BEAM that spawned it — so the caller would deadlock. With
  --no-block the call returns, systemd kills the BEAM asynchronously, and
  LiveView reconnects to the new BEAM.

  ## Injection

  All external effects are injectable for tests:

  * `:cmd_fn` — `(binary, [args]) -> {output, exit_code}`
  * `:env_fn` — `(name) -> value | nil` (defaults to `System.get_env/1`)
  * `:cgroup_reader` — `() -> {:ok, binary} | {:error, term}` (defaults to
    `File.read("/proc/self/cgroup")`)
  """

  require MediaCentarr.Log, as: Log

  @default_unit "media-centarr.service"

  @type state :: %{
          under_systemd: boolean(),
          unit_name: String.t() | nil,
          systemd_available: boolean(),
          unit_installed: boolean(),
          active: boolean(),
          enabled: boolean()
        }

  @doc """
  Returns the current systemd state for whichever media-centarr unit this
  BEAM is running under (dev, showcase, or prod), or the default unit name
  as a fallback when detection yields nothing.
  """
  @spec state(keyword()) :: state()
  def state(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    env_fn = Keyword.get(opts, :env_fn, &System.get_env/1)
    cgroup_reader = Keyword.get(opts, :cgroup_reader, &default_cgroup_reader/0)

    under = under_systemd?(env_fn)
    # cgroup only names *our* unit when we're actually supervised. When
    # started by hand, the cgroup path reflects the calling shell, not us.
    detected_unit = if under, do: detect_unit(cgroup_reader)
    unit = detected_unit || @default_unit
    available = systemd_available?(cmd_fn)

    %{
      under_systemd: under,
      unit_name: detected_unit,
      systemd_available: available,
      unit_installed: available and unit_installed?(cmd_fn, unit),
      active: available and active?(cmd_fn, unit),
      enabled: available and enabled?(cmd_fn, unit)
    }
  end

  @doc """
  Returns the systemd unit this BEAM is supervised by, or `nil` if it
  isn't under systemd.

  Cheap: only reads `INVOCATION_ID` and `/proc/self/cgroup` — no
  `systemctl` shell-out. Safe to call from hot paths like LiveView mount.
  """
  @spec detected_unit(keyword()) :: String.t() | nil
  def detected_unit(opts \\ []) do
    env_fn = Keyword.get(opts, :env_fn, &System.get_env/1)
    cgroup_reader = Keyword.get(opts, :cgroup_reader, &default_cgroup_reader/0)

    if under_systemd?(env_fn), do: detect_unit(cgroup_reader)
  end

  @doc """
  Queues a restart of the detected unit (or the default unit as fallback)
  with `--no-block` so the caller doesn't deadlock on its own BEAM being
  killed.
  """
  @spec restart(keyword()) :: :ok | {:error, term()}
  def restart(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    unit = resolve_unit(opts)
    Log.info(:system, "restarting #{unit} via systemctl --user")

    case cmd_fn.("systemctl", ["--user", "--no-block", "restart", unit]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:systemctl_failed, code, String.trim(output)}}
    end
  end

  @doc """
  Queues a stop of the detected unit (or the default unit as fallback).
  After this returns, the app is no longer running; the user must
  `systemctl --user start <unit>` (or re-enable autostart) to bring it back.
  """
  @spec stop(keyword()) :: :ok | {:error, term()}
  def stop(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    unit = resolve_unit(opts)
    Log.info(:system, "stopping #{unit} via systemctl --user")

    case cmd_fn.("systemctl", ["--user", "--no-block", "stop", unit]) do
      {_output, 0} -> :ok
      {output, code} -> {:error, {:systemctl_failed, code, String.trim(output)}}
    end
  end

  @doc """
  Returns the textual output of `systemctl --user status` for the detected
  unit.

  systemctl returns a non-zero exit code when the unit is inactive or
  failed; we treat both zero and non-zero exits as success from the
  read's perspective — the output is what the user wants to see either
  way. Only a true error (command not found, etc.) returns an error.
  """
  @spec status_output(keyword()) :: {:ok, String.t()} | {:error, term()}
  def status_output(opts \\ []) do
    cmd_fn = Keyword.get(opts, :cmd_fn, &default_cmd/2)
    unit = resolve_unit(opts)

    try do
      {output, _code} =
        cmd_fn.("systemctl", ["--user", "status", unit, "--no-pager"])

      {:ok, output}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end

  # --- Internals ---

  defp resolve_unit(opts) do
    cgroup_reader = Keyword.get(opts, :cgroup_reader, &default_cgroup_reader/0)
    detect_unit(cgroup_reader) || @default_unit
  end

  defp under_systemd?(env_fn) do
    case env_fn.("INVOCATION_ID") do
      nil -> false
      "" -> false
      _ -> true
    end
  end

  defp detect_unit(cgroup_reader) do
    case cgroup_reader.() do
      {:ok, contents} -> parse_cgroup_unit(contents)
      _ -> nil
    end
  end

  # Scans each line for a "*.service" segment and returns the last one
  # found. cgroup v2 has a single line like "0::/user.slice/.../<unit>.service";
  # v1 has multiple "controller:path" lines, and we prefer the deepest
  # match. The path separator is always "/", so we split on "/" regardless
  # of controller prefix.
  defp parse_cgroup_unit(contents) when is_binary(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.map(&extract_service_from_line/1)
    |> Enum.reject(&is_nil/1)
    |> List.last()
  end

  defp parse_cgroup_unit(_), do: nil

  defp extract_service_from_line(line) do
    line
    |> String.split("/")
    |> Enum.reverse()
    |> Enum.find(&String.ends_with?(&1, ".service"))
  end

  defp default_cgroup_reader, do: File.read("/proc/self/cgroup")

  defp systemd_available?(cmd_fn) do
    case cmd_fn.("systemctl", ["--user", "show-environment"]) do
      {_output, 0} -> true
      _ -> false
    end
  catch
    _, _ -> false
  end

  defp unit_installed?(cmd_fn, unit) do
    # `list-unit-files` succeeds even for inactive units as long as the
    # file exists on disk.
    case cmd_fn.("systemctl", ["--user", "list-unit-files", unit, "--no-pager"]) do
      {output, 0} -> String.contains?(output, unit)
      _ -> false
    end
  end

  defp active?(cmd_fn, unit) do
    case cmd_fn.("systemctl", ["--user", "is-active", unit]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  defp enabled?(cmd_fn, unit) do
    case cmd_fn.("systemctl", ["--user", "is-enabled", unit]) do
      {_output, 0} -> true
      _ -> false
    end
  end

  # Forward the env vars systemctl needs (XDG_RUNTIME_DIR,
  # DBUS_SESSION_BUS_ADDRESS) while explicitly blanking known secrets
  # out of the child's environment.
  #
  # Elixir 1.19's `System.cmd/3` requires env values to be binaries (nil/false
  # tuples raise FunctionClauseError inside `String.to_charlist/1`), so
  # secrets are blanked to `""` rather than unset — `systemctl` doesn't read
  # them either way, and the blank value still prevents leakage.
  #
  # The binary is resolved via `System.find_executable/1` up-front to sidestep
  # PATH-lookup quirks observed when `env:` is passed on OTP 28.
  defp default_cmd(binary, args) do
    resolved = System.find_executable(binary) || binary

    keep =
      Enum.flat_map(["XDG_RUNTIME_DIR", "DBUS_SESSION_BUS_ADDRESS"], fn name ->
        case System.get_env(name) do
          nil -> []
          "" -> []
          value -> [{name, value}]
        end
      end)

    redacted =
      Enum.map(
        [
          "SECRET_KEY_BASE",
          "TMDB_API_KEY",
          "PROWLARR_API_KEY",
          "DOWNLOAD_CLIENT_PASSWORD"
        ],
        &{&1, ""}
      )

    System.cmd(resolved, args, stderr_to_stdout: true, env: keep ++ redacted)
  rescue
    ErlangError -> {"", 127}
  end
end
