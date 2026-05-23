defmodule MediaCentaur.Platform.Autostart do
  @moduledoc """
  Process-supervision seam — behaviour + facade.

  Encapsulates the OS-specific autostart system that supervises the
  running media-centaur release:

  * **Linux** — systemd-user (`Platform.Autostart.Systemd`).
    `INVOCATION_ID` for detection, `systemctl --user` for control,
    `/proc/self/cgroup` for unit-name discovery.
  * **macOS** — launchd (`Platform.Autostart.Launchd`, future
    phase). `launchctl print pid/$$` for detection, `launchctl
    kickstart/bootout` for control, plist `Label` for unit-name.

  Three concerns live behind this seam, all owned by "the autostart
  system" architecturally:

  1. **State + control** — `state/1`, `detected_unit/1`, `restart/1`,
     `stop/1`, `status_output/1`. Consumed by `SelfUpdate` (Settings
     card).
  2. **Handoff env list** — `handoff_env_vars/0`. The env-var names
     `SelfUpdate.Handoff` must forward through `env -i` so the
     detached installer can reach the user's supervisor. Linux needs
     XDG/DBUS; macOS launchd resolves from the caller's UID and
     needs nothing. Belongs to the supervisor, not the spawner.
  3. **Tarball contract** — `tarball_required_paths/0`. The
     OS-specific unit-file path `SelfUpdate.Stager` must find in
     incoming release tarballs. Linux ships
     `share/systemd/media-centaur.service`; macOS will ship
     `share/launchd/com.media-centaur.app.plist`. Belongs to the
     supervisor, not the stager.

  ## Usage

      iex> MediaCentaur.Platform.Autostart.detected_unit()
      "media-centaur.service" | nil

  The facade reads the impl from
  `Application.get_env(:media_centaur, __MODULE__, ...)`, defaulting
  to `Systemd`. Tests override via `Application.put_env/3`.
  """

  @type state :: %{
          under_systemd: boolean(),
          unit_name: String.t() | nil,
          systemd_available: boolean(),
          unit_installed: boolean(),
          active: boolean(),
          enabled: boolean()
        }

  @callback state(opts :: keyword()) :: state()
  @callback detected_unit(opts :: keyword()) :: String.t() | nil
  @callback restart(opts :: keyword()) :: :ok | {:error, term()}
  @callback stop(opts :: keyword()) :: :ok | {:error, term()}
  @callback status_output(opts :: keyword()) :: {:ok, String.t()} | {:error, term()}
  @callback handoff_env_vars() :: [String.t()]
  @callback tarball_required_paths() :: [String.t()]

  @doc "Current autostart-system state for this BEAM's unit."
  @spec state(keyword()) :: state()
  def state(opts \\ []), do: impl().state(opts)

  @doc "Detected unit name from the autostart system, or `nil`."
  @spec detected_unit(keyword()) :: String.t() | nil
  def detected_unit(opts \\ []), do: impl().detected_unit(opts)

  @doc "Queue a restart of the autostart-managed unit."
  @spec restart(keyword()) :: :ok | {:error, term()}
  def restart(opts \\ []), do: impl().restart(opts)

  @doc "Queue a stop of the autostart-managed unit."
  @spec stop(keyword()) :: :ok | {:error, term()}
  def stop(opts \\ []), do: impl().stop(opts)

  @doc "Textual status output for the unit (e.g. `systemctl status` body)."
  @spec status_output(keyword()) :: {:ok, String.t()} | {:error, term()}
  def status_output(opts \\ []), do: impl().status_output(opts)

  @doc """
  Env-var names `SelfUpdate.Handoff` must forward through `env -i`
  so the detached installer can reach this OS's user-supervisor.
  """
  @spec handoff_env_vars() :: [String.t()]
  def handoff_env_vars, do: impl().handoff_env_vars()

  @doc """
  Paths that release tarballs must contain so `SelfUpdate.Stager`
  knows the bundled installer has the right unit-file for this OS.
  """
  @spec tarball_required_paths() :: [String.t()]
  def tarball_required_paths, do: impl().tarball_required_paths()

  defp impl do
    MediaCentaur.Platform.pick_impl(__MODULE__,
      linux: MediaCentaur.Platform.Autostart.Systemd,
      darwin: MediaCentaur.Platform.Autostart.Launchd
    )
  end
end
