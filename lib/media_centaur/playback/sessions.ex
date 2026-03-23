defmodule MediaCentaur.Playback.Sessions do
  @moduledoc """
  Public API for playback sessions. Replaces the former singleton Manager.

  This is a stateless facade — no GenServer. All state lives in individual
  MpvSession processes, discovered via SessionRegistry.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Playback.{MpvSession, SessionRegistry, SessionSupervisor}

  @doc """
  Starts playback for the given params. Returns `:ok` or `{:error, reason}`.

  If a session is already active for the entity, returns `{:error, :already_playing}`.
  """
  def play(params) do
    entity_id = params.entity_id

    if SessionRegistry.active?(entity_id) do
      {:error, :already_playing}
    else
      Log.info(:playback, "play requested — #{params[:entity_name] || entity_id}")

      case SessionSupervisor.start_session(params) do
        {:ok, _pid} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Returns a list of `%{entity_id, state, now_playing}` for all active sessions.
  """
  def list do
    SessionRegistry.list()
    |> Enum.map(fn {entity_id, _pid} ->
      case MpvSession.get_state(entity_id) do
        nil -> nil
        snapshot -> Map.put(snapshot, :entity_id, entity_id)
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Returns the state snapshot for one entity_id, or nil."
  def get(entity_id), do: MpvSession.get_state(entity_id)

  @doc "Returns true if the given entity_id has an active session."
  def playing?(entity_id), do: SessionRegistry.active?(entity_id)
end
