defmodule MediaCentarr.Playback.Supervisor do
  @moduledoc """
  Groups playback infrastructure: SessionRegistry, SessionSupervisor, and
  a one-shot recovery task.

  Uses `:one_for_one` — children are independent. Registry auto-deregisters
  dead processes. SessionSupervisor crash kills all sessions (they're temporary
  and will be re-discovered via recovery on next restart).
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [
        {Registry, keys: :unique, name: MediaCentarr.Playback.SessionRegistry},
        MediaCentarr.Playback.SessionSupervisor
      ] ++ recovery_children()

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end

  # Skipped in test (config/test.exs) because the recovery scan reads from
  # `mpv_socket_dir` and would attach to mpv instances the user is running on
  # the dev box, leaking real playback sessions into every test that mounts a
  # LiveView with `Playback.subscribe()`.
  defp recovery_children do
    if Application.get_env(:media_centarr, :start_playback_recovery, true) do
      [{Task, &recover_sessions/0}]
    else
      []
    end
  end

  defp recover_sessions do
    alias MediaCentarr.Playback.{SessionRecovery, SessionSupervisor}
    require MediaCentarr.Log, as: Log

    for params <- SessionRecovery.recover_all() do
      case SessionSupervisor.start_session(params) do
        {:ok, _pid} ->
          Log.info(:playback, "recovered session — #{params[:entity_name] || params.entity_id}")

        {:error, reason} ->
          Log.warning(
            :playback,
            "failed to recover session — #{params.entity_id}: #{inspect(reason)}"
          )
      end
    end
  end
end
