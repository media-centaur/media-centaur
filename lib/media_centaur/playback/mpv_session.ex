defmodule MediaCentaur.Playback.MpvSession do
  @moduledoc """
  Per-session GenServer managing one MPV process via Port + Unix domain socket IPC.

  Each session tracks one entity's *viewing chain*, identified by entity_id.
  The socket path is `media-centaur-{entity_id}.sock` in the configured socket dir.
  Sessions register in `SessionRegistry` by entity_id for lookup and enumeration.

  This is an observation-only tracker — the user controls mpv directly.
  The session observes position/duration/pause/eof via IPC, persists watch
  progress, and broadcasts state changes via PubSub.

  ## Episode auto-advance (ADR-062)

  A TV episode session appends its successor to the mpv playlist
  (`NextEpisode.resolve/1`), so end-of-episode rolls into the next file
  inside the same mpv process — no window teardown, no HDR re-lock. The
  queueing decision runs off mpv's own `playlist-count`/`playlist-pos`
  properties: the successor is appended only while the current entry is
  the playlist's last, which makes the check self-stabilizing (the append
  bumps the count, disarming it) and reconnect-safe (an entry queued
  before a backend restart is respected, never duplicated). A `path`
  change is the advance signal: the session closes out the finished
  episode, re-points its identity at the file now playing, and queues the
  next successor. Quit-on-EOF only ever fires at true playlist end —
  `eof-reached` stays false across mid-playlist transitions.

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

  mpv is launched with `--log-file=<socket_dir>/media-centaur-<session_id>.log`
  so the exit classifier has a real error string to work with even when
  `--no-terminal` blocks port-data capture. `MpvLogReader.fallback_tail/3`
  prefers the live port tail when present and falls back to the log file
  otherwise. The log file is cleaned up on session stop alongside the IPC
  socket.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Progress, as: LibraryProgress

  alias MediaCentaur.Platform.DisplayEnv

  alias MediaCentaur.Playback.{
    ChapterCompletion,
    Events,
    IpcFraming,
    LanguageContext,
    MpvExitClassifier,
    MpvLogReader,
    NextEpisode,
    OverrideCapture,
    ProgressBroadcaster,
    SessionRegistry,
    TrackResolver,
    WatchingTracker
  }

  @db_write_interval_ms 10_000
  @socket_retry_interval_ms 200

  # Brief window after the first exit signal (tcp_closed OR exit_status) to let
  # the other signal and any final stderr chunks arrive before classifying.
  @exit_debounce_ms 200

  # Debounce window for capturing user track changes — coalesces rapid
  # keyboard mashing (e.g. #-#-# to cycle audio) into a single capture.
  @track_capture_debounce_ms 3_000

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
    state: :starting,
    language_context: nil,
    # mpv `chapter-list` for the loaded file (`[%{"title", "time"}]`), used
    # by `ChapterCompletion` to complete at the credits boundary rather than
    # grinding to the 90%/eof fallback. Empty for files without chapters.
    chapters: [],
    audio_tracks: [],
    subtitle_tracks: [],
    # Raw mpv-reported selected track indices (not derived languages). The
    # comparison languages are resolved from these against the *complete*
    # track list at capture time — see `LanguageContext.current_selection/4`
    # and the `perform_capture/1` note — so an early `sid` event that lands
    # before subtitle tracks demux can't freeze a stale "no subs" baseline.
    current_aid: nil,
    current_sid: nil,
    resolver_choice: nil,
    # Last `sid` value we pushed to mpv via enforcement, so we only send
    # `set_property sid` when the resolved target actually changes (no IPC
    # spam, no enforcement loop). `nil` = nothing enforced yet.
    enforced_sid: nil,
    capture_timer: nil,
    # The successor episode appended to the mpv playlist and not yet
    # reached (ADR-062). `nil` while nothing is queued — chain end,
    # auto-play off, or a non-episode session.
    pending_next: nil,
    # Mirror of mpv's playlist shape, fed by property observation. The
    # queue check appends only while `playlist_count - playlist_pos == 1`.
    playlist_count: 1,
    playlist_pos: 0,
    # Carries the unterminated tail of the mpv IPC byte stream between
    # `{:tcp, ...}` deliveries. The socket is `packet: :raw`, so a long
    # JSON line (e.g. `track-list`) can span chunks — `IpcFraming.feed/2`
    # stitches them back together.
    ipc_buffer: ""
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
    socket_dir = MediaCentaur.Config.get(:mpv_socket_dir)
    socket_path = Path.join(socket_dir, "media-centaur-#{params.entity_id}.sock")
    log_file_path = Path.join(socket_dir, "media-centaur-#{session_id}.log")
    timeout_ms = MediaCentaur.Config.get(:mpv_socket_timeout_ms)
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
      started_at: System.monotonic_time(:millisecond),
      language_context: LanguageContext.init(params)
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
           [:binary, packet: :raw, active: true],
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
          "Media Centaur can't reach your desktop. Restart it after signing in."
        )

        {:stop, :normal, %{state | state: :stopped}}
    end
  end

  def handle_info(:connect_socket, state) do
    socket_path = to_charlist(state.socket_path)

    case :gen_tcp.connect({:local, socket_path}, 0, [:binary, packet: :raw, active: true]) do
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
          timeout_ms = MediaCentaur.Config.get(:mpv_socket_timeout_ms)
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
    # The socket is `packet: :raw`: a chunk may hold several IPC lines or
    # only part of one (mpv's `track-list` regularly exceeds the read
    # buffer). Stitch via the carried buffer, then decode each complete
    # line. Decoding a fragment in isolation would raise Jason.DecodeError.
    {lines, buffer} = IpcFraming.feed(state.ipc_buffer, data)
    state = Enum.reduce(lines, %{state | ipc_buffer: buffer}, &decode_ipc_line/2)
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

  # Debounced capture — fires after the user has settled on a track
  # selection. Compares current state against what the resolver chose
  # at episode start; persists an override only if they differ.
  def handle_info(:capture_settled, state) do
    perform_capture(state)
    {:noreply, %{state | capture_timer: nil}}
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
    mpv_path = MediaCentaur.Config.get(:mpv_path)

    language_flags = LanguageContext.to_mpv_flags(state.language_context.priority_args)

    flags =
      [
        "--fullscreen",
        "--no-terminal",
        "--msg-level=all=error",
        "--force-window=immediate",
        "--input-ipc-server=#{state.socket_path}",
        "--log-file=#{state.log_file_path}"
      ] ++
        language_flags ++
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

        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          ProgressBroadcaster.broadcast_extra(entity_id, extra_id)
        end)

      # Entity/episode/movie playback — broadcast entity progress update
      session.movie_id || session.episode_id || session.video_object_id ->
        entity_id = session.entity_id

        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          # Explicit nil: this is the end-of-playback summary refresh. The
          # per-tick broadcast in persist_progress/1 already carried the
          # changed playable_item_id, so there is no single record to
          # report here.
          ProgressBroadcaster.broadcast(entity_id, nil)
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

  # Decode one complete IPC line (already newline-framed by IpcFraming)
  # and fold its effect into the session state. Blank lines (the trailing
  # split segment of a "…}\n" chunk) are skipped.
  defp decode_ipc_line(line, state) do
    case String.trim(line) do
      "" ->
        state

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, message} ->
            state
            |> flag_property_event(message)
            |> then(&handle_mpv_message(message, &1))

          {:error, error} ->
            Log.warning(:playback, "IPC JSON decode failed — #{inspect(error)}")
            state
        end
    end
  end

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

  defp handle_mpv_message(%{"event" => "end-file"}, %{pending_next: nil} = state) do
    finalize(state)
  end

  # Mid-chain end-file: mpv is advancing into the queued entry, not
  # exiting. Save the outgoing episode's progress now, while `position`
  # and `chapters` still describe the finished file — the new file's
  # property events would clobber them before the `path` change lands.
  # If this end-file is actually a quit, the exit-classification path
  # still finalizes the session moments later.
  defp handle_mpv_message(%{"event" => "end-file"}, state) do
    if state.tracker.actively_watching, do: persist_progress(state)
    state
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "track-list", "data" => tracks},
         state
       )
       when is_list(tracks) do
    handle_track_list_update(state, tracks)
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "chapter-list", "data" => chapters},
         state
       )
       when is_list(chapters) do
    %{state | chapters: chapters}
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "playlist-count", "data" => count},
         state
       )
       when is_integer(count) do
    maybe_queue_next(%{state | playlist_count: count})
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "playlist-pos", "data" => pos},
         state
       )
       when is_integer(pos) do
    maybe_queue_next(%{state | playlist_pos: pos})
  end

  # `path` is nil between files; the initial observation echoes the file
  # we launched. Only a change to a different file is an advance.
  defp handle_mpv_message(%{"event" => "property-change", "name" => "path", "data" => path}, state)
       when is_binary(path) do
    if path == state.content_url do
      state
    else
      advance_to(state, path)
    end
  end

  defp handle_mpv_message(%{"event" => "property-change", "name" => "aid", "data" => aid}, state) do
    schedule_capture(%{state | current_aid: aid})
  end

  defp handle_mpv_message(%{"event" => "property-change", "name" => "sid", "data" => sid}, state) do
    schedule_capture(%{state | current_sid: sid})
  end

  defp handle_mpv_message(_message, state), do: state

  # --- Episode auto-advance (ADR-062) ---

  # Append the successor episode while the current entry is the
  # playlist's last. Runs off every playlist-count/playlist-pos change
  # and after each advance; all other states are no-ops, so the check is
  # idempotent — an entry queued by a previous backend run (reconnect)
  # keeps the count ahead and is never duplicated.
  defp maybe_queue_next(state) do
    if is_nil(state.pending_next) and not is_nil(state.episode_id) and
         not is_nil(state.socket) and not state.exiting? and
         state.playlist_count - state.playlist_pos == 1 do
      queue_next(state)
    else
      state
    end
  end

  defp queue_next(state) do
    case NextEpisode.resolve(state.episode_id) do
      {:ok, item} ->
        send_mpv_command(state.socket, NextEpisode.loadfile_command(item))

        Log.info(
          :playback,
          "queued next episode — S#{item.season_number}E#{item.episode_number} #{Path.basename(item.content_url)}"
        )

        %{state | pending_next: item}

      :none ->
        state
    end
  end

  # A playlist advance landed on a new file: re-point the session at the
  # episode now playing. Identity comes from the queued item when the
  # path matches; otherwise it is re-derived from the path (the ADR-023
  # discipline — covers entries queued before a backend restart). The
  # outgoing episode's final progress was persisted at its end-file.
  defp advance_to(state, path) do
    identity =
      case state.pending_next do
        %{content_url: ^path} = item -> {:ok, item}
        _ -> NextEpisode.identify(state.entity_id, path)
      end

    case identity do
      {:ok, item} ->
        Log.info(
          :playback,
          "advanced to S#{item.season_number}E#{item.episode_number} — #{Path.basename(path)}"
        )

        state = reset_for_file(state, path, %{episode_id: item.episode_id}, item)
        broadcast_state_changed(state.state, state)
        maybe_queue_next(state)

      :none ->
        # A file this session can't attribute (user loaded something
        # into mpv by hand, or the library changed underneath). Stop
        # attributing progress rather than corrupting the old episode's.
        Log.warning(
          :playback,
          "playlist advanced to unrecognized file — #{Path.basename(path)}; progress attribution stops"
        )

        reset_for_file(
          state,
          path,
          %{episode_id: nil, movie_id: nil, video_object_id: nil},
          %{season_number: nil, episode_number: nil, episode_name: nil}
        )
    end
  end

  defp reset_for_file(state, path, fk_fields, item) do
    if state.capture_timer, do: Process.cancel_timer(state.capture_timer)

    Map.merge(
      %{
        state
        | content_url: path,
          season_number: item.season_number,
          episode_number: item.episode_number,
          episode_name: item.episode_name,
          start_position: 0.0,
          position: 0.0,
          duration: 0.0,
          tracker: WatchingTracker.new(),
          chapters: [],
          audio_tracks: [],
          subtitle_tracks: [],
          current_aid: nil,
          current_sid: nil,
          resolver_choice: nil,
          enforced_sid: nil,
          capture_timer: nil,
          pending_next: nil,
          last_db_write_at: System.monotonic_time(:millisecond),
          state: if(state.paused, do: :paused, else: :playing)
      },
      fk_fields
    )
  end

  # --- Language / track override capture ---

  # Recompute the resolver choice on *every* track-list update, not just
  # the first. mpv populates tracks incrementally — audio frequently
  # demuxes before subtitles — so the first non-empty list can be
  # audio-only, which would otherwise freeze a wrong "no subs" baseline.
  # track-list changes come only from mpv (initial load, external sub
  # file); a user switching tracks fires `aid`/`sid`, never track-list,
  # so recomputing here never clobbers a deliberate user selection.
  defp handle_track_list_update(state, raw_tracks) do
    {audio_tracks, subtitle_tracks} = LanguageContext.parse_track_list(raw_tracks)
    state = %{state | audio_tracks: audio_tracks, subtitle_tracks: subtitle_tracks}

    if audio_tracks == [] and subtitle_tracks == [] do
      state
    else
      result = resolve_tracks(state)
      new_choice = capture_choice(result)

      if new_choice != state.resolver_choice do
        Log.info(:playback, "track-resolver: " <> Enum.join(result.decision_log, " | "))
      end

      enforce_subtitle_selection(%{state | resolver_choice: new_choice}, result)
    end
  end

  defp resolve_tracks(state) do
    ctx = state.language_context

    TrackResolver.resolve(
      ctx.policy,
      ctx.override,
      state.audio_tracks,
      state.subtitle_tracks,
      ctx.original_language
    )
  end

  # The lang-based slice of the resolution, used as the override-capture
  # baseline (lang/forced, not indices — survives re-rips).
  defp capture_choice(result) do
    %{
      audio_lang: result.audio_lang,
      sub_lang: result.sub_lang,
      sub_forced: result.sub_forced
    }
  end

  # Resolver is the source of truth: once subtitle tracks exist, make mpv's
  # `sid` match `resolve/5`'s pick (disabling subs when it chose none).
  # Gated on subtitle tracks being present (`sid_enforcement/2` returns
  # `:skip` for an empty list) so we don't flash subs off during the
  # audio-only incremental-load window. Idempotent — only sends when the
  # resolved target changes. Driven from `track-list` updates only; a
  # *user* track switch fires `sid`, never `track-list`, so enforcement
  # never clobbers a deliberate selection, and our own `set_property sid`
  # echo lands on the `sid` handler (capture), not here — no loop.
  defp enforce_subtitle_selection(state, result) do
    case TrackResolver.sid_enforcement(result, state.subtitle_tracks) do
      :skip ->
        state

      {:set, sid} ->
        if sid == state.enforced_sid do
          state
        else
          send_mpv_command(state.socket, ["set_property", "sid", sid])
          Log.info(:playback, "track-resolver: enforcing sid=#{inspect(sid)}")
          %{state | enforced_sid: sid}
        end
    end
  end

  # No capture for unsupported entity types (extras, video objects) — skip
  # scheduling rather than computing-and-discarding to avoid spurious
  # timer churn.
  defp schedule_capture(%{language_context: %{owner_type: nil}} = state), do: state
  defp schedule_capture(%{resolver_choice: nil} = state), do: state

  defp schedule_capture(state) do
    if state.capture_timer, do: Process.cancel_timer(state.capture_timer)
    timer = Process.send_after(self(), :capture_settled, @track_capture_debounce_ms)
    %{state | capture_timer: timer}
  end

  defp perform_capture(%{language_context: %{owner_type: nil}}), do: :ok
  defp perform_capture(%{resolver_choice: nil}), do: :ok

  defp perform_capture(state) do
    # Resolve the user's *current* selection now, from the complete track
    # lists — not from a language snapshot taken when the `aid`/`sid` event
    # fired. mpv populates tracks incrementally and auto-selects a sub from
    # our `--slang` before subtitle tracks demux, so an event-time snapshot
    # can read "no subs" while the eng sub is in fact selected. Deriving here
    # is what stops the per-series `subtitles_off` poison (the Frieren
    # flip-flop) — see `LanguageContext.current_selection/4`.
    current_state =
      LanguageContext.current_selection(
        state.current_aid,
        state.current_sid,
        state.audio_tracks,
        state.subtitle_tracks
      )

    case OverrideCapture.compute(state.resolver_choice, current_state) do
      :no_change ->
        :ok

      {:override, attrs} ->
        persist_track_override(state.language_context, attrs)
    end
  end

  defp persist_track_override(%{owner_type: owner_type, owner_id: owner_id}, attrs) do
    case Library.MediaTrackOverrides.upsert(owner_type, owner_id, attrs) do
      {:ok, _override} ->
        Log.info(
          :playback,
          "captured track override (#{owner_type}=#{Format.short_id(owner_id)}) — #{inspect(attrs)}"
        )

        Events.broadcast(%Events.TrackOverrideChanged{
          owner_type: owner_type,
          owner_id: owner_id
        })

      {:error, changeset} ->
        Log.warning(
          :playback,
          "failed to persist track override — #{inspect(changeset.errors)}"
        )
    end
  end

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

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      case MediaCentaur.Library.ProgressRecords.find_or_create_for_extra(params) do
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

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
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

          maybe_mark_completed_via_progress(playable_item_id, saveable, duration, state.chapters)
          # Preserve the rich `%EntityProgressUpdated{}` event for
          # consumers that need summary/resume_target/changed_record
          # (EntityModal, StatusLive, LibraryLive). The simpler
          # `{:entity_progress_updated, pi_id, pos}` tuple broadcast
          # from Progress.record/3 is consumed by projections that
          # only need the trigger.
          #
          # Thread `playable_item_id` so the payload carries the changed
          # record — without it the detail modal's in-memory merge
          # no-ops and a per-episode badge never flips live (it only
          # corrects on a full remount).
          ProgressBroadcaster.broadcast(entity_id, playable_item_id)

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
      case Library.Containers.fetch(:movie, movie_id) do
        {:ok, %{position: pos}} when is_integer(pos) -> pos
        _ -> 1
      end

    case Library.PlayableItems.find_or_create(:movie, movie_id, position) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(%{episode_id: episode_id}) when not is_nil(episode_id) do
    position =
      case Library.Episodes.fetch(episode_id) do
        {:ok, %{episode_number: n}} when is_integer(n) -> n
        _ -> 1
      end

    case Library.PlayableItems.find_or_create(:episode, episode_id, position) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(%{video_object_id: vo_id}) when not is_nil(vo_id) do
    case Library.PlayableItems.find_or_create(:video_object, vo_id, 1) do
      {:ok, %{id: id}} -> {:ok, id}
      other -> other
    end
  end

  defp resolve_or_create_playable_item_id(_params), do: {:error, :no_fk_specified}

  defp maybe_mark_completed_via_progress(playable_item_id, position, duration, chapters)
       when is_number(position) and is_number(duration) and duration > 0 do
    case LibraryProgress.get(playable_item_id) do
      %{completed: true} ->
        :ok

      _ ->
        case completion_reason(position, duration, chapters) do
          nil ->
            :ok

          reason ->
            Log.info(:playback, "marked completed — #{reason}")
            :ok = LibraryProgress.complete(playable_item_id)
        end
    end
  end

  defp maybe_mark_completed_via_progress(_playable_item_id, _position, _duration, _chapters), do: :ok

  # Returns a human-readable reason string when the item should be marked
  # completed, or `nil` otherwise. Two triggers:
  #
  #   * a credits/outro chapter — the user reached the end of *content*,
  #     independent of how long the credits tail runs; and
  #   * the 90% position fallback, for the majority of files that carry no
  #     usable chapter markers.
  #
  # The chapter trigger is checked first so a title with a long tail
  # completes at the credits boundary instead of grinding to 90%.
  defp completion_reason(position, duration, chapters) do
    cond do
      (content_end = ChapterCompletion.content_end_seconds(chapters, duration)) &&
          position >= content_end ->
        "reached credits chapter at #{Format.format_seconds(content_end)}"

      position / duration >= 0.90 ->
        "#{Format.format_seconds(position)} reached #{Float.round(position / duration * 100, 0)}% of #{Format.format_seconds(duration)}"

      true ->
        nil
    end
  end

  defp maybe_mark_extra_completed(record, position, duration)
       when is_number(position) and is_number(duration) and duration > 0 do
    if not record.completed and position / duration >= 0.90 do
      Log.info(
        :playback,
        "extra marked completed — #{Float.round(position / duration * 100, 0)}%"
      )

      case MediaCentaur.Library.ProgressRecords.mark_completed(record) do
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
    send_mpv_command(socket, ["observe_property", 5, "track-list"])
    send_mpv_command(socket, ["observe_property", 6, "aid"])
    send_mpv_command(socket, ["observe_property", 7, "sid"])
    send_mpv_command(socket, ["observe_property", 8, "chapter-list"])
    send_mpv_command(socket, ["observe_property", 9, "playlist-count"])
    send_mpv_command(socket, ["observe_property", 10, "playlist-pos"])
    send_mpv_command(socket, ["observe_property", 11, "path"])
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
