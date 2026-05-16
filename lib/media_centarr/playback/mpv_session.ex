defmodule MediaCentarr.Playback.MpvSession do
  @moduledoc """
  Per-session GenServer managing one MPV process via Port + Unix domain socket IPC.

  Each session tracks a single entity's playback, identified by entity_id.
  The socket path is `media-centarr-{entity_id}.sock` in the configured socket dir.
  Sessions register in `SessionRegistry` by entity_id for lookup and enumeration.

  This is an observation-only tracker — the user controls mpv directly.
  The session observes position/duration/pause/eof via IPC, persists watch
  progress, and broadcasts state changes via PubSub.

  ## Display environment

  Before spawning mpv, `DisplayEnv.resolve/1` produces an env list with
  `WAYLAND_DISPLAY` / `DISPLAY` (preferring parent-env values, falling back to
  scanning `$XDG_RUNTIME_DIR/wayland-N` and `/tmp/.X11-unix/XN`). This protects
  against the classic failure mode where the service was started before the
  graphical session imported its env into systemd-user — without it, mpv aborts
  with status 1 and `--no-terminal` swallows the error message. When neither
  display server is reachable, the session broadcasts `PlaybackFailed` with
  `reason: :no_display` and stops, surfacing a clear user-facing message
  instead of a silent mpv failure.

  ## Diagnostic capture

  mpv is launched with `--log-file=<socket_dir>/media-centarr-<session_id>.log`
  so the exit classifier has a real error string to work with even when
  `--no-terminal` blocks port-data capture. `MpvLogReader.fallback_tail/3`
  prefers the live port tail when present and falls back to the log file
  otherwise. The log file is cleaned up on session stop alongside the IPC
  socket.
  """
  use GenServer
  require MediaCentarr.Log, as: Log

  alias MediaCentarr.Format
  alias MediaCentarr.Library
  alias MediaCentarr.Library.{Episode, Movie}
  alias MediaCentarr.Library.Progress, as: LibraryProgress

  alias MediaCentarr.Playback.{
    DisplayEnv,
    Events,
    MpvExitClassifier,
    MpvLogReader,
    ProgressBroadcaster,
    SessionRegistry,
    WatchingTracker
  }

  alias MediaCentarr.Repo

  @db_write_interval_ms 10_000
  @socket_retry_interval_ms 200

  # Brief window after the first exit signal (tcp_closed OR exit_status) to let
  # the other signal and any final stderr chunks arrive before classifying.
  @exit_debounce_ms 200

  defstruct [
    :session_id,
    :entity_id,
    :entity_name,
    :season_number,
    :episode_number,
    :episode_name,
    :extra_id,
    :movie_id,
    :episode_id,
    :video_object_id,
    :content_url,
    :start_position,
    :socket_path,
    :log_file_path,
    :port,
    :socket,
    :position,
    :duration,
    :paused,
    :last_db_write_at,
    :socket_retries,
    :tracker,
    :started_at,
    :exit_status,
    seen_property_event?: false,
    output_tail: [],
    exiting?: false,
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

    session_id = Base.encode16(:crypto.strong_rand_bytes(4), case: :lower)
    socket_dir = MediaCentarr.Config.get(:mpv_socket_dir)
    socket_path = Path.join(socket_dir, "media-centarr-#{params.entity_id}.sock")
    log_file_path = Path.join(socket_dir, "media-centarr-#{session_id}.log")
    timeout_ms = MediaCentarr.Config.get(:mpv_socket_timeout_ms)
    max_retries = div(timeout_ms, @socket_retry_interval_ms)

    state = %__MODULE__{
      session_id: session_id,
      entity_id: params.entity_id,
      entity_name: params[:entity_name],
      season_number: params[:season_number],
      episode_number: params[:episode_number],
      episode_name: params[:episode_name],
      extra_id: params[:extra_id],
      movie_id: params[:movie_id],
      episode_id: params[:episode_id],
      video_object_id: params[:video_object_id],
      content_url: params.content_url,
      start_position: params[:start_position] || 0.0,
      socket_path: socket_path,
      log_file_path: log_file_path,
      position: 0.0,
      duration: 0.0,
      paused: false,
      last_db_write_at: System.monotonic_time(:millisecond),
      socket_retries: max_retries,
      tracker: WatchingTracker.new(),
      started_at: System.monotonic_time(:millisecond)
    }

    Log.info(:playback, "session started — #{Path.basename(params.content_url)}")
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
        Log.info(:playback, "reconnect failed, cleaning stale socket, launching fresh")
        File.rm(state.socket_path)
        send(self(), :launch_mpv)
        {:noreply, state}
    end
  end

  def handle_info(:launch_mpv, state) do
    case DisplayEnv.resolve() do
      {:ok, env_pairs} ->
        spawn_mpv(state, env_pairs)

      {:error, :no_display} ->
        Log.error(
          :playback,
          "no display server reachable — refusing to launch mpv (service likely started before the graphical session)"
        )

        broadcast_playback_failed(
          state,
          :no_display,
          "Media Centarr can't reach your desktop. Restart it after signing in."
        )

        {:stop, :normal, %{state | state: :stopped}}
    end
  end

  def handle_info(:connect_socket, state) do
    socket_path = to_charlist(state.socket_path)

    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: true]) do
      {:ok, socket} ->
        Log.info(:playback, "connected to IPC socket")
        observe_properties(socket)

        if state.start_position > 0 do
          Log.info(:playback, "resuming at #{Format.format_seconds(state.start_position)}")
        end

        broadcast_state_changed(:playing, state)
        {:noreply, %{state | socket: socket, state: :playing}}

      {:error, _reason} ->
        if state.socket_retries > 0 do
          timeout_ms = MediaCentarr.Config.get(:mpv_socket_timeout_ms)
          max_retries = div(timeout_ms, @socket_retry_interval_ms)

          if state.socket_retries == max_retries do
            Log.info(:playback, "waiting for IPC socket (#{max_retries} retries)")
          end

          Process.send_after(self(), :connect_socket, @socket_retry_interval_ms)
          {:noreply, %{state | socket_retries: state.socket_retries - 1}}
        else
          Log.error(:playback, "socket connect timed out")
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
        {:ok, message} ->
          state
          |> flag_property_event(message)
          |> then(&handle_mpv_message(message, &1))

        {:error, error} ->
          Log.warning(:playback, "IPC JSON decode failed — #{inspect(error)}")
          state
      end

    {:noreply, state}
  end

  # MPV socket closed
  def handle_info({:tcp_closed, _socket}, state) do
    Log.info(:playback, "socket closed")
    schedule_exit_classification(%{state | socket: nil})
  end

  # MPV process exited
  def handle_info({_port, {:exit_status, status}}, state) do
    Log.info(:playback, "mpv exited — status #{status}")
    schedule_exit_classification(%{state | exit_status: status})
  end

  # MPV stdout+stderr (merged via :stderr_to_stdout). Captured into a
  # bounded tail for later classification and logged live so failures
  # are diagnosable in the Console / journal without re-running.
  def handle_info({_port, {:data, data}}, state) do
    log_mpv_lines(data)
    {:noreply, %{state | output_tail: MpvExitClassifier.append_output(state.output_tail, data)}}
  end

  # Debounced classification — fires after the first exit signal gives
  # both signals + any trailing output time to arrive.
  def handle_info(:classify_and_finalize, state) do
    {:stop, :normal, finalize_with_classification(state)}
  end

  # Absorb EXIT messages from port link (required with trap_exit)
  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    finalize(state)
    cleanup(state)
    :ok
  end

  # --- mpv launch ---

  defp spawn_mpv(state, env_pairs) do
    Log.info(:playback, "launching mpv — #{Path.basename(state.content_url)}")
    mpv_path = MediaCentarr.Config.get(:mpv_path)

    flags =
      [
        "--fullscreen",
        "--no-terminal",
        "--msg-level=all=error",
        "--force-window=immediate",
        "--input-ipc-server=#{state.socket_path}",
        "--log-file=#{state.log_file_path}"
      ] ++
        if(state.start_position > 0, do: ["--start=#{state.start_position}"], else: []) ++
        [state.content_url]

    port =
      Port.open({:spawn_executable, to_charlist(mpv_path)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:env, env_pairs},
        args: flags
      ])

    Process.send_after(self(), :connect_socket, @socket_retry_interval_ms)
    {:noreply, %{state | port: port}}
  end

  # --- Idempotent Finalization ---
  # Guard prevents double-finalize on already-stopped sessions.

  defp finalize(%{state: session_state} = session) when session_state in [:playing, :paused] do
    if session.tracker.actively_watching, do: persist_progress(session)

    cond do
      # Extra playback — broadcast extra progress update
      session.extra_id ->
        entity_id = session.entity_id
        extra_id = session.extra_id

        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          ProgressBroadcaster.broadcast_extra(entity_id, extra_id)
        end)

      # Entity/episode/movie playback — broadcast entity progress update
      session.movie_id || session.episode_id || session.video_object_id ->
        entity_id = session.entity_id

        Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
          ProgressBroadcaster.broadcast(entity_id)
        end)

      # No progress tracking (shouldn't happen, but safe fallback)
      true ->
        :ok
    end

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
      Log.info(:playback, "actively watching")
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

  defp handle_mpv_message(%{"event" => "property-change", "name" => "pause", "data" => paused}, state)
       when is_boolean(paused) do
    new_state = if paused, do: :paused, else: :playing
    Log.info(:playback, if(paused, do: "paused", else: "resumed"))
    state = %{state | paused: paused, state: new_state}

    if paused and state.tracker.actively_watching, do: persist_progress(state)
    broadcast_state_changed(new_state, state)

    state
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "eof-reached", "data" => true},
         state
       ) do
    Log.info(:playback, "reached end of file")
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

  # --- Progress Persistence ---

  defp persist_progress(%{extra_id: extra_id} = state) when not is_nil(extra_id) do
    persist_extra_progress(state)
  end

  defp persist_progress(%{movie_id: nil, episode_id: nil, video_object_id: nil}), do: :ok

  defp persist_progress(state) do
    persist_entity_progress(state)
  end

  defp persist_extra_progress(state) do
    saveable = state.tracker.saveable_position || state.position
    duration = state.duration

    params = %{
      extra_id: state.extra_id,
      entity_id: state.entity_id,
      position_seconds: saveable,
      duration_seconds: duration
    }

    entity_id = state.entity_id
    extra_id = state.extra_id

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      case MediaCentarr.Library.find_or_create_extra_progress(params) do
        {:ok, record} ->
          Log.info(
            :playback,
            "saved extra progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
          )

          maybe_mark_extra_completed(record, saveable, duration)
          ProgressBroadcaster.broadcast_extra(entity_id, extra_id)

        {:error, reason} ->
          Log.warning(:playback, "failed to save extra progress — #{inspect(reason)}")
      end
    end)
  end

  defp persist_entity_progress(state) do
    saveable = state.tracker.saveable_position || state.position
    duration = state.duration

    params =
      %{
        position_seconds: saveable,
        duration_seconds: duration
      }
      |> maybe_put(:movie_id, state.movie_id)
      |> maybe_put(:episode_id, state.episode_id)
      |> maybe_put(:video_object_id, state.video_object_id)

    entity_id = state.entity_id

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      case resolve_or_create_playable_item_id(params) do
        {:ok, playable_item_id} ->
          # Hot-path write: lands in the Library.Progress in-memory
          # table in microseconds; the debounced flush persists to
          # `library_watch_progress` on the next interval (default 5s)
          # or synchronously on clean shutdown (Library Schema v2
          # Phase 3 Task D).
          :ok = LibraryProgress.record(playable_item_id, saveable, duration)

          Log.info(
            :playback,
            "saved progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
          )

          maybe_mark_completed_via_progress(playable_item_id, saveable, duration)
          # Preserve the rich `%EntityProgressUpdated{}` event for
          # consumers that need summary/resume_target/changed_record
          # (EntityModal, StatusLive, LibraryLive). The simpler
          # `{:entity_progress_updated, pi_id, pos}` tuple broadcast
          # from Progress.record/3 is consumed by projections that
          # only need the trigger.
          ProgressBroadcaster.broadcast(entity_id)

        {:error, reason} ->
          Log.warning(:playback, "failed to save progress — #{inspect(reason)}")
      end
    end)
  end

  # Resolves the canonical PlayableItem for the session's container FK
  # without writing any WatchProgress row — that's the new Progress
  # GenServer's job. Mirrors `Library.find_or_create_watch_progress_for_*`
  # but stops at the PlayableItem.
  defp resolve_or_create_playable_item_id(%{movie_id: movie_id}) when not is_nil(movie_id) do
    position =
      case Repo.get(Movie, movie_id) do
        %{position: pos} when is_integer(pos) -> pos
        _ -> 1
      end

    case Library.find_or_create_playable_item(:movie, movie_id, position) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(%{episode_id: episode_id}) when not is_nil(episode_id) do
    position =
      case Repo.get(Episode, episode_id) do
        %{episode_number: n} when is_integer(n) -> n
        _ -> 1
      end

    case Library.find_or_create_playable_item(:episode, episode_id, position) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(%{video_object_id: vo_id}) when not is_nil(vo_id) do
    case Library.find_or_create_playable_item(:video_object, vo_id, 1) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(_params), do: {:error, :no_fk_specified}

  defp maybe_mark_completed_via_progress(playable_item_id, position, duration)
       when is_number(position) and is_number(duration) and duration > 0 do
    case LibraryProgress.get(playable_item_id) do
      %{completed: true} ->
        :ok

      _ ->
        if position / duration >= 0.90 do
          Log.info(
            :playback,
            "marked completed — #{Format.format_seconds(position)} reached #{Float.round(position / duration * 100, 0)}% of #{Format.format_seconds(duration)}"
          )

          :ok = LibraryProgress.complete(playable_item_id)
        else
          :ok
        end
    end
  end

  defp maybe_mark_completed_via_progress(_playable_item_id, _position, _duration), do: :ok

  defp maybe_mark_extra_completed(record, position, duration)
       when is_number(position) and is_number(duration) and duration > 0 do
    if not record.completed and position / duration >= 0.90 do
      Log.info(
        :playback,
        "extra marked completed — #{Float.round(position / duration * 100, 0)}%"
      )

      case MediaCentarr.Library.mark_extra_completed(record) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Log.warning(:playback, "failed to mark extra completed — #{inspect(reason)}")
      end
    end

    :ok
  end

  defp maybe_mark_extra_completed(_record, _position, _duration), do: :ok

  # --- PubSub Broadcasting ---

  defp broadcast_state_changed(new_state, session) do
    now_playing = build_now_playing_for_broadcast(new_state, session)

    Events.broadcast(%Events.PlaybackStateChanged{
      entity_id: session.entity_id,
      state: new_state,
      now_playing: now_playing,
      started_at: session.started_at
    })
  end

  defp build_now_playing_for_broadcast(new_state, session) when new_state in [:playing, :paused] do
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
      if state.log_file_path, do: File.rm(state.log_file_path)
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

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp flag_property_event(state, %{"event" => "property-change"}),
    do: %{state | seen_property_event?: true}

  defp flag_property_event(state, _message), do: state

  # --- Exit Classification ---

  defp schedule_exit_classification(%{exiting?: true} = state), do: {:noreply, state}

  defp schedule_exit_classification(state) do
    Process.send_after(self(), :classify_and_finalize, @exit_debounce_ms)
    {:noreply, %{state | exiting?: true}}
  end

  defp finalize_with_classification(state) do
    classification =
      MpvExitClassifier.classify(%{
        seen_property_event?: state.seen_property_event?,
        exit_status: state.exit_status,
        output_tail: MpvLogReader.fallback_tail(state.output_tail, state.log_file_path, 5)
      })

    case classification do
      {:ok, :ended} ->
        finalize(state)

      {:error, :startup_failure, message} ->
        Log.error(:playback, "mpv startup failure — #{message}")
        broadcast_playback_failed(state, :startup_failure, message)
        finalize(state)
    end
  end

  defp broadcast_playback_failed(session, reason, message) do
    Events.broadcast(%Events.PlaybackFailed{
      entity_id: session.entity_id,
      reason: reason,
      payload: %{
        message: message,
        entity_name: session.entity_name,
        season_number: session.season_number,
        episode_number: session.episode_number,
        episode_name: session.episode_name,
        content_url: session.content_url
      }
    })
  end

  defp log_mpv_lines(data) do
    data
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      trimmed = String.trim(line)
      if trimmed != "", do: Log.info(:playback, "mpv: #{trimmed}")
    end)
  end
end
