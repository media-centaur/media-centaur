defmodule MediaCentaur.Playback.Supervisor do
  @moduledoc """
  Groups playback infrastructure: SessionRegistry, SessionSupervisor, and,
  where background work runs, the SessionWatchdog (recovers the mpv a
  crashed session leaves) and a one-shot recovery task. The watchdog
  starts first, so the sessions boot recovery starts are watched.

  `:rest_for_one`: the sessions register in `SessionRegistry` and a remote
  player's channel in `PlayerRegistry`, so a registry restart restarts the
  session supervisor after it — a session that kept running unregistered
  would be unreachable by key and a second play of its entity would start a
  twin on the same mpv. Sessions are temporary; a restart of the session
  supervisor loses them and the recovery task reattaches to the mpvs on the
  next boot (ADR-023).
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [
        {Registry, keys: :unique, name: MediaCentaur.Playback.SessionRegistry},
        {Registry, keys: :unique, name: MediaCentaur.Playback.Transport.Remote.PlayerRegistry},
        MediaCentaur.Playback.SessionSupervisor
      ] ++ recovery_children()

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 30)
  end

  # Background work: only in an instance with `background_services` on
  # (`Settings.Config`). Under :test the recovery scan would read
  # `mpv_socket_dir` and attach to mpv instances the user is running on
  # the dev box, leaking real playback sessions into every test that mounts
  # a LiveView with `Playback.subscribe()`.
  defp recovery_children do
    if MediaCentaur.Settings.Config.get(:background_services) do
      [MediaCentaur.Playback.SessionWatchdog, {Task, &recover_sessions/0}]
    else
      []
    end
  end

  defp recover_sessions, do: MediaCentaur.Playback.Sessions.recover(:host)
end
