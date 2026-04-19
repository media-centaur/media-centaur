defmodule MediaCentarr.Playback.Sessions do
  @moduledoc """
  Public API for playback sessions. Replaces the former singleton Manager.

  This is a stateless facade — no GenServer. All state lives in individual
  MpvSession processes, discovered via SessionRegistry.
  """
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Playback.{MpvSession, SessionRegistry, SessionSupervisor}

  @doc """
  Starts playback for the given params. Returns `:ok` or `{:error, reason}`.

  If a session is already active for the entity, returns `{:error, :already_playing}`.
  """
  def play(params) do
    entity_id = params.entity_id

    cond do
      not playable_file?(params) ->
        Log.error(:playback, "file not available — #{params[:content_url]}")
        {:error, :file_not_found}

      SessionRegistry.active?(entity_id) ->
        Log.info(:playback, "already playing — #{params[:entity_name] || entity_id}")
        {:error, :already_playing}

      true ->
        Log.info(:playback, "starting session — #{params[:entity_name] || entity_id}")

        case SessionSupervisor.start_session(params) do
          {:ok, _pid} ->
            :ok

          {:error, reason} ->
            Log.info(:playback, "session start failed — #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  defp playable_file?(%{content_url: path}) when is_binary(path), do: File.exists?(path)
  defp playable_file?(_params), do: false

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
