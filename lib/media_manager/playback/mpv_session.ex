defmodule MediaManager.Playback.MpvSession do
  @moduledoc """
  Per-session GenServer managing one MPV process via Port + Unix domain socket IPC.
  Launched by the Playback Manager for each play command.
  """
  use GenServer
  require Logger

  @db_write_interval_ms 5_000
  @pubsub_broadcast_interval_ms 2_000
  @socket_retry_interval_ms 200

  defstruct [
    :session_id,
    :entity_id,
    :season_number,
    :episode_number,
    :content_url,
    :start_position,
    :socket_path,
    :port,
    :socket,
    :position,
    :duration,
    :paused,
    :last_db_write_at,
    :last_broadcast_at,
    :socket_retries,
    state: :starting
  ]

  # --- Public API ---

  def start_link(params) do
    GenServer.start_link(__MODULE__, params)
  end

  def pause(pid), do: GenServer.call(pid, :pause)
  def stop(pid), do: GenServer.call(pid, :stop)
  def seek(pid, position), do: GenServer.call(pid, {:seek, position})

  # --- Callbacks ---

  @impl true
  def init(params) do
    session_id = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    socket_dir = MediaManager.Config.get(:mpv_socket_dir)
    socket_path = Path.join(socket_dir, "freedia-mpv-#{session_id}.sock")
    timeout_ms = MediaManager.Config.get(:mpv_socket_timeout_ms)
    max_retries = div(timeout_ms, @socket_retry_interval_ms)

    state = %__MODULE__{
      session_id: session_id,
      entity_id: params.entity_id,
      season_number: params[:season_number],
      episode_number: params[:episode_number],
      content_url: params.content_url,
      start_position: params[:start_position] || 0.0,
      socket_path: socket_path,
      position: 0.0,
      duration: 0.0,
      paused: false,
      last_db_write_at: System.monotonic_time(:millisecond),
      last_broadcast_at: System.monotonic_time(:millisecond),
      socket_retries: max_retries
    }

    send(self(), :launch_mpv)
    {:ok, state}
  end

  @impl true
  def handle_call(:pause, _from, %{state: session_state} = state)
      when session_state in [:playing, :paused] do
    toggle = not state.paused
    send_mpv_command(state.socket, ["set_property", "pause", toggle])
    {:reply, :ok, state}
  end

  def handle_call(:pause, _from, state) do
    {:reply, {:error, :not_playing}, state}
  end

  @impl true
  def handle_call(:stop, _from, %{state: session_state} = state)
      when session_state in [:playing, :paused] do
    send_mpv_command(state.socket, ["quit"])
    {:reply, :ok, state}
  end

  def handle_call(:stop, _from, state) do
    {:reply, {:error, :not_playing}, state}
  end

  @impl true
  def handle_call({:seek, position}, _from, %{state: session_state} = state)
      when session_state in [:playing, :paused] do
    send_mpv_command(state.socket, ["seek", position, "absolute"])
    {:reply, :ok, state}
  end

  def handle_call({:seek, _position}, _from, state) do
    {:reply, {:error, :not_playing}, state}
  end

  @impl true
  def handle_info(:launch_mpv, state) do
    mpv_path = MediaManager.Config.get(:mpv_path)

    flags = [
      "--fullscreen",
      "--no-terminal",
      "--force-window=immediate",
      "--input-ipc-server=#{state.socket_path}",
      state.content_url
    ]

    port =
      Port.open({:spawn_executable, to_charlist(mpv_path)}, [
        :binary,
        :exit_status,
        args: flags
      ])

    Process.send_after(self(), :connect_socket, @socket_retry_interval_ms)
    {:noreply, %{state | port: port}}
  end

  @impl true
  def handle_info(:connect_socket, state) do
    socket_path = to_charlist(state.socket_path)

    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :line, active: true]) do
      {:ok, socket} ->
        Logger.info("MpvSession #{state.session_id}: connected to IPC socket")
        send_mpv_command(socket, ["observe_property", 1, "time-pos"])
        send_mpv_command(socket, ["observe_property", 2, "duration"])
        send_mpv_command(socket, ["observe_property", 3, "pause"])
        send_mpv_command(socket, ["observe_property", 4, "eof-reached"])

        if state.start_position > 0 do
          send_mpv_command(socket, ["seek", state.start_position, "absolute"])
        end

        broadcast_state_changed(:playing, state)
        {:noreply, %{state | socket: socket, state: :playing}}

      {:error, _reason} ->
        if state.socket_retries > 0 do
          Process.send_after(self(), :connect_socket, @socket_retry_interval_ms)
          {:noreply, %{state | socket_retries: state.socket_retries - 1}}
        else
          Logger.error("MpvSession #{state.session_id}: socket connect timeout")
          cleanup(state)
          {:stop, :normal, %{state | state: :stopped}}
        end
    end
  end

  # MPV IPC data
  @impl true
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
  @impl true
  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("MpvSession #{state.session_id}: socket closed")
    persist_progress(state)
    broadcast_entity_progress(state)
    broadcast_state_changed(:stopped, state)
    cleanup(state)
    {:stop, :normal, %{state | state: :stopped}}
  end

  # MPV process exited
  @impl true
  def handle_info({_port, {:exit_status, status}}, state) do
    Logger.info("MpvSession #{state.session_id}: MPV exited with status #{status}")
    persist_progress(state)
    broadcast_entity_progress(state)
    broadcast_state_changed(:stopped, state)
    cleanup(state)
    {:stop, :normal, %{state | state: :stopped}}
  end

  # Ignore MPV stdout/stderr output
  @impl true
  def handle_info({_port, {:data, _data}}, state), do: {:noreply, state}

  # --- MPV Message Handling ---

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "time-pos", "data" => pos},
         state
       )
       when is_number(pos) do
    state = %{state | position: pos}
    maybe_persist(state) |> maybe_broadcast(state)
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "duration", "data" => dur},
         state
       )
       when is_number(dur) do
    %{state | duration: dur}
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "pause", "data" => paused},
         state
       )
       when is_boolean(paused) do
    new_state = if paused, do: :paused, else: :playing
    state = %{state | paused: paused, state: new_state}

    if paused, do: persist_progress(state)
    broadcast_state_changed(new_state, state)

    state
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "eof-reached", "data" => true},
         state
       ) do
    persist_progress(state)
    broadcast_entity_progress(state)
    broadcast_state_changed(:stopped, state)
    send_mpv_command(state.socket, ["quit"])
    state
  end

  defp handle_mpv_message(%{"event" => "end-file"}, state) do
    persist_progress(state)
    broadcast_entity_progress(state)
    broadcast_state_changed(:stopped, state)
    cleanup(state)
    state
  end

  defp handle_mpv_message(_message, state), do: state

  # --- Debounced DB Writes ---

  defp maybe_persist(state) do
    now = System.monotonic_time(:millisecond)

    if now - state.last_db_write_at >= @db_write_interval_ms do
      persist_progress(state)
      %{state | last_db_write_at: now}
    else
      state
    end
  end

  # --- Debounced PubSub Broadcasts ---

  defp maybe_broadcast(state, old_state) do
    now = System.monotonic_time(:millisecond)

    if now - old_state.last_broadcast_at >= @pubsub_broadcast_interval_ms do
      Phoenix.PubSub.broadcast(
        MediaManager.PubSub,
        "playback:events",
        {:playback_progress,
         %{position_seconds: state.position, duration_seconds: state.duration}}
      )

      %{state | last_broadcast_at: now}
    else
      state
    end
  end

  # --- Entity Progress Broadcasting ---

  defp broadcast_entity_progress(session) do
    case Ash.get(MediaManager.Library.Entity, session.entity_id, action: :with_associations) do
      {:ok, entity} ->
        progress_records = entity.watch_progress || []
        summary = MediaManager.Playback.ProgressSummary.compute(entity, progress_records)

        Phoenix.PubSub.broadcast(
          MediaManager.PubSub,
          "playback:events",
          {:entity_progress_updated, session.entity_id, summary}
        )

      {:error, _} ->
        :ok
    end
  end

  # --- Progress Persistence ---

  defp persist_progress(state) do
    params = %{
      entity_id: state.entity_id,
      season_number: state.season_number,
      episode_number: state.episode_number,
      position_seconds: state.position,
      duration_seconds: state.duration
    }

    case Ash.create(MediaManager.Library.WatchProgress, params, action: :upsert_progress) do
      {:ok, _} -> :ok
      {:error, reason} -> Logger.warning("MpvSession: progress write failed: #{inspect(reason)}")
    end
  end

  # --- PubSub Broadcasting ---

  defp broadcast_state_changed(new_state, session) do
    now_playing =
      if new_state in [:playing, :paused] do
        %{
          entity_id: session.entity_id,
          season_number: session.season_number,
          episode_number: session.episode_number,
          content_url: session.content_url,
          position_seconds: session.position,
          duration_seconds: session.duration
        }
      else
        nil
      end

    Phoenix.PubSub.broadcast(
      MediaManager.PubSub,
      "playback:events",
      {:playback_state_changed, new_state, now_playing}
    )
  end

  # --- Cleanup ---

  defp cleanup(state) do
    if state.socket do
      :gen_tcp.close(state.socket)
    end

    File.rm(state.socket_path)
  end

  defp send_mpv_command(nil, _command), do: :ok

  defp send_mpv_command(socket, command) do
    json = Jason.encode!(%{"command" => command}) <> "\n"
    :gen_tcp.send(socket, json)
  end
end
