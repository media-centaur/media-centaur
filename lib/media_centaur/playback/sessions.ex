defmodule MediaCentaur.Playback.Sessions do
  @moduledoc """
  Public API for playback sessions: a stateless facade over the
  `MpvSession` processes `SessionRegistry` finds by `{player, entity_id}`.

  A session plays on a **player**: `:host` (an mpv this computer spawns,
  `Transport.Local`) or a paired player's id (an mpv on that device over
  its channel). Playback takes the player as a value and never reads the
  `Players` context, as it takes a profile id and never reads `Profiles`.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Playback.{MpvSession, SessionRegistry, SessionSupervisor, Transport}

  @type player :: SessionRegistry.player()

  @doc """
  Starts playback of `params` on `player`. Returns `:ok` or `{:error, reason}`:
  `:file_not_found` when the file is not on disk, `:already_playing` when
  that player already plays that entity, `:player_offline` when a remote
  player has no channel to this install. `params.profile_id` is required:
  the profile the session records under.
  """
  @spec play(map(), player()) ::
          :ok | {:error, :file_not_found | :already_playing | :player_offline | term()}
  def play(params, player) do
    entity_id = params.entity_id
    key = {player, entity_id}

    cond do
      not playable_file?(params) ->
        Log.error(:playback, "file not available — #{params[:content_url]}")
        {:error, :file_not_found}

      SessionRegistry.active?(key) ->
        Log.info(:playback, "already playing — #{params[:entity_name] || entity_id}")
        {:error, :already_playing}

      true ->
        start(params, player)
    end
  end

  @doc """
  Reattaches a session to an mpv that outlived its last one (`SessionRecovery`):
  the params already name the file, the position and the profile, and
  `reattach?: true` tells the transport to observe rather than load.
  """
  @spec resume(map(), player()) :: :ok | {:error, term()}
  def resume(params, player), do: start(Map.put(params, :reattach?, true), player)

  defp start(params, player) do
    with {:ok, transport} <- transport_for(params, player) do
      Log.info(
        :playback,
        "starting session — #{params[:entity_name] || params.entity_id} on #{inspect(player)}"
      )

      case SessionSupervisor.start_session(Map.merge(params, %{player: player, transport: transport})) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Log.info(:playback, "session start failed — #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # A caller may hand in the transport (a test's fake); otherwise the player
  # decides it.
  defp transport_for(%{transport: transport}, _player), do: {:ok, transport}
  defp transport_for(%{entity_id: entity_id}, :host), do: {:ok, Transport.Local.new(entity_id)}
  defp transport_for(_params, player_id) when is_binary(player_id), do: Transport.Remote.new(player_id)

  defp playable_file?(%{content_url: path}) when is_binary(path), do: File.exists?(path)
  defp playable_file?(_params), do: false

  @doc """
  Returns a list of `%{player, entity_id, state, now_playing, started_at}`
  for all active sessions.
  """
  @spec list() :: [map()]
  def list do
    SessionRegistry.list()
    |> Enum.map(fn {{player, entity_id} = key, _pid} ->
      case MpvSession.get_state(key) do
        nil -> nil
        snapshot -> Map.merge(snapshot, %{player: player, entity_id: entity_id})
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Ends one player's viewing of one entity: the session finalises (progress
  saved, `:stopped` and `SessionEnded` broadcast) and releases its
  transport. `:ok` whether or not a session was running.
  """
  @spec stop(player(), String.t()) :: :ok
  def stop(player, entity_id) do
    case SessionRegistry.lookup({player, entity_id}) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  catch
    :exit, _already_gone -> :ok
  end

  @doc "Returns the state snapshot for one player's viewing of one entity, or nil."
  @spec get(player(), String.t()) :: map() | nil
  def get(player, entity_id) do
    case MpvSession.get_state({player, entity_id}) do
      nil -> nil
      snapshot -> Map.merge(snapshot, %{player: player, entity_id: entity_id})
    end
  end
end
