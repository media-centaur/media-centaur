defmodule MediaCentaur.Playback.Sessions do
  @moduledoc """
  Public API for playback sessions: a stateless facade over the
  `MpvSession` processes `SessionRegistry` finds by `{player, entity_id}`.

  A session plays on a **player**: `:host` (an mpv this computer spawns,
  `Transport.Local`) or a paired player's id (an mpv on that device over
  its channel). Playback takes the player as a value and never reads the
  `Players` context, as it takes a profile id and never reads `Profiles`.
  The player's kind is read here and nowhere else, to choose the
  transport (`transport_for/2`); what else differs between the kinds the
  transport answers — a transport that holds one viewing at a time has
  `play/2` end the player's other viewings first.
  """
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Playback
  alias MediaCentaur.Playback.{MpvSession, SessionRegistry, SessionSupervisor, Transport}

  @doc """
  Starts playback of `params` on `player`. Returns `:ok` or `{:error, reason}`:
  `:file_not_found` when the file is not on disk, `:already_playing` when
  that player already plays that entity, `:player_offline` when a remote
  player has no channel to this install. `params.profile_id` is required:
  the profile the session records under. On a player whose transport
  holds one viewing at a time, the player's other viewings end first, as
  a deliberate stop: a `loadfile … replace` would otherwise take the file
  from under a session that would then observe a file it did not start.
  """
  @spec play(map(), Playback.player()) ::
          :ok | {:error, :file_not_found | :already_playing | :player_offline | term()}
  def play(params, player) do
    entity_id = params.entity_id

    cond do
      not playable_file?(params) ->
        Log.error(:playback, "file not available — #{params[:content_url]}")
        {:error, :file_not_found}

      SessionRegistry.active?({player, entity_id}) ->
        Log.info(:playback, "already playing — #{params[:entity_name] || entity_id}")
        {:error, :already_playing}

      true ->
        with {:ok, transport} <- transport_for(params, player) do
          if Transport.holds_one_viewing?(transport), do: stop_all(player)
          start(params, player, transport)
        end
    end
  end

  defp stop_all(player) do
    for {{^player, entity_id}, _pid} <- SessionRegistry.list() do
      Log.info(:playback, "replacing the viewing on #{inspect(player)} — #{entity_id}")
      stop(player, entity_id)
    end

    :ok
  end

  @doc """
  Reattaches a session to an mpv that outlived its last one (`SessionRecovery`):
  the params already name the file, the position and the profile, and
  `reattach?: true` tells the transport to observe rather than load.
  """
  @spec resume(map(), Playback.player()) :: :ok | {:error, term()}
  def resume(params, player) do
    with {:ok, transport} <- transport_for(params, player),
         do: start(Map.put(params, :reattach?, true), player, transport)
  end

  defp start(params, player, transport) do
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

  # A caller may hand in the transport (a test's fake); otherwise the player's
  # transport module builds it.
  defp transport_for(%{transport: transport}, _player), do: {:ok, transport}
  defp transport_for(params, player), do: transport_module(player).for_player(player, params)

  # The one place the player's kind is read.
  defp transport_module(:host), do: Transport.Local
  defp transport_module(player_id) when is_binary(player_id), do: Transport.Remote

  @doc """
  Reattaches sessions to the mpvs on `player` that outlived their last
  session (ADR-023): the host's orphaned processes at boot, a remote
  player's mpv when its channel connects and no session holds it. The
  player's transport finds them and reads what they play
  (`Transport.recover/1`), `SessionRecovery` turns the readings into
  reattach params, and each starts through `resume/2`.
  """
  @spec recover(Playback.player()) :: :ok
  def recover(player) do
    for params <- transport_module(player).recover(player) do
      case resume(params, player) do
        :ok ->
          Log.info(
            :playback,
            "recovered session — #{params[:entity_name] || params.entity_id} on #{inspect(player)}"
          )

        {:error, reason} ->
          Log.warning(
            :playback,
            "failed to recover session — #{params.entity_id} on #{inspect(player)}: #{inspect(reason)}"
          )
      end
    end

    :ok
  end

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
  @spec stop(Playback.player(), String.t()) :: :ok
  def stop(player, entity_id) do
    case SessionRegistry.lookup({player, entity_id}) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  catch
    :exit, _already_gone -> :ok
  end

  @doc "Sends a reader's `Playback.Command` to one player's viewing of one entity."
  @spec command(Playback.player(), String.t(), Playback.Command.t()) :: :ok | {:error, :no_session}
  def command(player, entity_id, command), do: MpvSession.command({player, entity_id}, command)

  @doc "Returns the state snapshot for one player's viewing of one entity, or nil."
  @spec get(Playback.player(), String.t()) :: map() | nil
  def get(player, entity_id) do
    case MpvSession.get_state({player, entity_id}) do
      nil -> nil
      snapshot -> Map.merge(snapshot, %{player: player, entity_id: entity_id})
    end
  end
end
