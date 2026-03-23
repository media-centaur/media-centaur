defmodule MediaCentaur.Playback.Supervisor do
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
    children = [
      {Registry, keys: :unique, name: MediaCentaur.Playback.SessionRegistry},
      MediaCentaur.Playback.SessionSupervisor,
      {Task, &recover_sessions/0}
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 30)
  end

  defp recover_sessions do
    alias MediaCentaur.Playback.{SessionRecovery, SessionSupervisor}
    require MediaCentaur.Log, as: Log

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
