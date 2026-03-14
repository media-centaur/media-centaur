defmodule MediaCentaur.Playback.MpvSession do
  @moduledoc """
  Per-session GenServer managing one MPV process via Port + Unix domain socket IPC.

  Each session tracks a single entity's playback, identified by entity_id.
  The socket path is `media-centaur-{entity_id}.sock` in the configured socket dir.
  Sessions register in `SessionRegistry` by entity_id for lookup and enumeration.

  This is an observation-only tracker — the user controls mpv directly.
  The session observes position/duration/pause/eof via IPC, persists watch
  progress, and broadcasts state changes via PubSub.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Playback.{ProgressBroadcaster, SessionRegistry, WatchingTracker}

  @db_write_interval_ms 10_000
  @socket_retry_interval_ms 200

  defstruct [
    :session_id,
    :entity_id,
    :entity_name,
    :season_number,
    :episode_number,
    :episode_name,
    :content_url,
    :start_position,
    :socket_path,
    :port,
    :socket,
    :position,
    :duration,
    :paused,
    :last_db_write_at,
    :socket_retries,
    :tracker,
    :started_at,
    state: :starting
  ]

  # --- Public API ---

  def start_link(params) do
    GenServer.start_link(__MODULE__, params, name: SessionRegistry.via(params.entity_id))
  end

  def child_spec(params) do
    %{
      id: {__MODULE__, params.entity_id},
      start: {__MODULE__, :start_link, [params]},
      restart: :temporary
    }
  end

  @doc "Returns a read-only snapshot of the session's current state."
  def get_state(entity_id) do
    case SessionRegistry.lookup(entity_id) do
      nil -> nil
      pid -> GenServer.call(pid, :get_state)
    end
  end

  # --- Callbacks ---

  @impl true
  def init(params) do
    Process.flag(:trap_exit, true)

    session_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    socket_dir = MediaCentaur.Config.get(:mpv_socket_dir)
    socket_path = Path.join(socket_dir, "media-centaur-#{params.entity_id}.sock")
    timeout_ms = MediaCentaur.Config.get(:mpv_socket_timeout_ms)
    max_retries = div(timeout_ms, @socket_retry_interval_ms)

    state = %__MODULE__{
      session_id: session_id,
      entity_id: params.entity_id,
      entity_name: params[:entity_name],
      season_number: params[:season_number],
      episode_number: params[:episode_number],
      episode_name: params[:episode_name],
      content_url: params.content_url,
      start_position: params[:start_position] || 0.0,
      socket_path: socket_path,
      position: 0.0,
      duration: 0.0,
      paused: false,
      last_db_write_at: System.monotonic_time(:millisecond),
      socket_retries: max_retries,
      tracker: WatchingTracker.new(),
      started_at: System.monotonic_time(:millisecond)
    }

    Log.info(:playback, "session #{session_id} init for #{Path.basename(params.content_url)}")
    send(self(), :try_reconnect)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    reply = %{
      state: state.state,
      now_playing: build_now_playing(state),
      started_at: state.started_at
    }

    {:reply, reply, state}
  end

  # Try to reconnect to an existing mpv process via the entity-scoped socket
  # before launching a new one. This handles the case where the backend restarts
  # while mpv is still running (ADR-023).
  @impl true
  def handle_info(:try_reconnect, state) do
    socket_charlist = to_charlist(state.socket_path)

    case :gen_tcp.connect(
           {:local, socket_charlist},
           0,
           [:binary, packet: :line, active: true],
           500
         ) do
      {:ok, socket} ->
        Log.info(
          :playback,
          "session #{state.session_id} reconnected to existing mpv via #{Path.basename(state.socket_path)}"
        )

        observe_properties(socket)
        broadcast_state_changed(:playing, state)
        {:noreply, %{state | socket: socket, state: :playing}}

      {:error, _reason} ->
        # No existing mpv — clean up stale socket file and launch fresh
        File.rm(state.socket_path)
        send(self(), :launch_mpv)
        {:noreply, state}
    end
  end

  def handle_info(:launch_mpv, state) do
    Log.info(:playback, "session #{state.session_id} launching mpv")
    mpv_path = MediaCentaur.Config.get(:mpv_path)

    flags =
      [
        "--fullscreen",
        "--no-terminal",
        "--force-window=immediate",
        "--input-ipc-server=#{state.socket_path}"
      ] ++
        if(state.start_position > 0, do: ["--start=#{state.start_position}"], else: []) ++
        [state.content_url]

    port =
      Port.open({:spawn_executable, to_charlist(mpv_path)}, [
        :binary,
        :exit_status,
        args: flags
      ])

    Process.send_after(self(), :connect_socket, @socket_retry_interval_ms)
    {:noreply, %{state | port: port}}
  end

  def handle_info(:connect_socket, state) do
    socket_path = to_charlist(state.socket_path)

    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: true]) do
      {:ok, socket} ->
        Log.info(:playback, "session #{state.session_id} connected to IPC socket")
        observe_properties(socket)

        if state.start_position > 0 do
          Log.info(:playback, "session #{state.session_id} resuming at #{state.start_position}s")
        end

        broadcast_state_changed(:playing, state)
        {:noreply, %{state | socket: socket, state: :playing}}

      {:error, _reason} ->
        if state.socket_retries > 0 do
          Process.send_after(self(), :connect_socket, @socket_retry_interval_ms)
          {:noreply, %{state | socket_retries: state.socket_retries - 1}}
        else
          Log.error(:playback, "session #{state.session_id}: socket connect timeout")
          {:stop, :normal, %{state | state: :stopped}}
        end
    end
  end

  # MPV IPC data — discard late messages after finalization
  def handle_info({:tcp, _socket, _data}, %{state: :stopped} = state) do
    {:noreply, state}
  end

  def handle_info({:tcp, _socket, data}, state) do
    state =
      data
      |> String.trim()
      |> Jason.decode()
      |> case do
        {:ok, message} -> handle_mpv_message(message, state)
        {:error, _} -> state
      end

    {:noreply, state}
  end

  # MPV socket closed
  def handle_info({:tcp_closed, _socket}, state) do
    Log.info(:playback, "session #{state.session_id} socket closed")
    {:stop, :normal, finalize(state)}
  end

  # MPV process exited
  def handle_info({_port, {:exit_status, status}}, state) do
    Log.info(:playback, "session #{state.session_id} mpv exited with status #{status}")
    {:stop, :normal, finalize(state)}
  end

  # Ignore MPV stdout/stderr output
  def handle_info({_port, {:data, _data}}, state), do: {:noreply, state}

  # Absorb EXIT messages from port link (required with trap_exit)
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    finalize(state)
    cleanup(state)
    :ok
  end

  # --- Idempotent Finalization ---
  # Guard prevents double-finalize on already-stopped sessions.

  defp finalize(%{state: session_state} = session) when session_state in [:playing, :paused] do
    if session.tracker.actively_watching, do: persist_progress(session)

    # Spawn entity progress broadcast to avoid blocking shutdown with DB queries
    entity_id = session.entity_id
    season_number = session.season_number
    episode_number = session.episode_number

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      broadcast_entity_progress_by_id(entity_id, season_number, episode_number)
    end)

    broadcast_state_changed(:stopped, session)
    %{session | state: :stopped}
  end

  defp finalize(session), do: %{session | state: :stopped}

  # --- MPV Message Handling ---

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "time-pos", "data" => position},
         state
       )
       when is_number(position) do
    now = System.monotonic_time(:millisecond)
    tracker = WatchingTracker.update(state.tracker, position, now)

    if tracker.actively_watching and not state.tracker.actively_watching do
      Log.info(:playback, "session #{state.session_id} actively watching")
    end

    state = %{state | position: position, tracker: tracker}
    maybe_persist(state)
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "duration", "data" => duration},
         state
       )
       when is_number(duration) do
    %{state | duration: duration}
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "pause", "data" => paused},
         state
       )
       when is_boolean(paused) do
    new_state = if paused, do: :paused, else: :playing
    Log.info(:playback, "session #{state.session_id} #{if paused, do: "paused", else: "resumed"}")
    state = %{state | paused: paused, state: new_state}

    if paused and state.tracker.actively_watching, do: persist_progress(state)
    broadcast_state_changed(new_state, state)

    state
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "eof-reached", "data" => true},
         state
       ) do
    Log.info(:playback, "session #{state.session_id} eof reached")
    state = finalize(state)
    send_mpv_command(state.socket, ["quit"])
    state
  end

  defp handle_mpv_message(%{"event" => "end-file"}, state) do
    finalize(state)
  end

  defp handle_mpv_message(_message, state), do: state

  # --- Debounced DB Writes ---

  defp maybe_persist(state) do
    now = System.monotonic_time(:millisecond)

    if state.tracker.actively_watching and now - state.last_db_write_at >= @db_write_interval_ms do
      persist_progress(state)
      %{state | last_db_write_at: now}
    else
      state
    end
  end

  # --- Entity Progress Broadcasting ---

  defp broadcast_entity_progress_by_id(entity_id, season_number, episode_number) do
    ProgressBroadcaster.broadcast(entity_id, season_number, episode_number)
  end

  # --- Progress Persistence ---

  defp persist_progress(state) do
    saveable = state.tracker.saveable_position || state.position
    session_id = state.session_id
    duration = state.duration

    season_number = state.season_number || 0
    episode_number = state.episode_number || 0

    params = %{
      entity_id: state.entity_id,
      season_number: season_number,
      episode_number: episode_number,
      position_seconds: saveable,
      duration_seconds: duration
    }

    entity_id = state.entity_id

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      case MediaCentaur.Library.upsert_watch_progress(params) do
        {:ok, record} ->
          Log.info(
            :playback,
            "session #{session_id} progress saved at #{Float.round(saveable, 1)}s"
          )

          maybe_mark_completed(record, saveable, duration)
          broadcast_entity_progress_by_id(entity_id, season_number, episode_number)

        {:error, reason} ->
          Log.warning(:playback, "progress write failed: #{inspect(reason)}")
      end
    end)
  end

  defp maybe_mark_completed(record, position, duration)
       when is_number(position) and is_number(duration) and duration > 0 do
    if not record.completed and position / duration >= 0.90 do
      Log.info(
        :playback,
        "marking episode completed at #{Float.round(position / duration * 100, 0)}%"
      )

      case MediaCentaur.Library.mark_watch_completed(record) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Log.warning(:playback, "mark_completed failed: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp maybe_mark_completed(_record, _position, _duration), do: :ok

  # --- PubSub Broadcasting ---

  defp broadcast_state_changed(new_state, session) do
    now_playing = build_now_playing_for_broadcast(new_state, session)

    Phoenix.PubSub.broadcast(
      MediaCentaur.PubSub,
      MediaCentaur.Topics.playback_events(),
      {:playback_state_changed, session.entity_id, new_state, now_playing, session.started_at}
    )
  end

  defp build_now_playing_for_broadcast(new_state, session)
       when new_state in [:playing, :paused] do
    build_now_playing(session)
  end

  defp build_now_playing_for_broadcast(_new_state, _session), do: nil

  defp build_now_playing(session) do
    %{
      entity_id: session.entity_id,
      entity_name: session.entity_name,
      season_number: session.season_number,
      episode_number: session.episode_number,
      episode_name: session.episode_name,
      content_url: session.content_url,
      position_seconds: session.position,
      duration_seconds: session.duration
    }
  end

  # --- Cleanup ---

  defp cleanup(state) do
    if state.socket do
      :gen_tcp.close(state.socket)
    end

    # Only delete the socket file if mpv has already exited.
    # If mpv is still running (backend shutting down), leave the socket
    # so recovery can reconnect on next startup (ADR-023).
    if state.state == :stopped do
      File.rm(state.socket_path)
    end
  end

  defp observe_properties(socket) do
    send_mpv_command(socket, ["observe_property", 1, "time-pos"])
    send_mpv_command(socket, ["observe_property", 2, "duration"])
    send_mpv_command(socket, ["observe_property", 3, "pause"])
    send_mpv_command(socket, ["observe_property", 4, "eof-reached"])
  end

  defp send_mpv_command(nil, _command), do: :ok

  defp send_mpv_command(socket, command) do
    json = Jason.encode!(%{"command" => command}) <> "\n"
    :gen_tcp.send(socket, json)
  end
end
