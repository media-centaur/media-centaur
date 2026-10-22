defmodule MediaCentaur.Playback.MpvSession do
  @moduledoc """
  Per-session GenServer observing one mpv through a `Playback.Transport`.

  Each session tracks one entity's *viewing chain*, identified by entity_id,
  on one **player** (`:host`, or a paired player's id), and holds the
  profile it was started for (`profile_id`, ADR-078) for its whole life —
  progress, track memory and every event it broadcasts are that profile's,
  and a switch mid-film does not re-home them. Every event names the
  player too. Sessions register in `SessionRegistry` by
  `{player, entity_id}` for lookup and enumeration.

  This is an observation-only tracker — the user controls mpv directly.
  The session observes position/duration/pause/eof over IPC, persists
  watch progress, and broadcasts state changes via PubSub. How the mpv is
  reached — a process the host spawns (`Transport.Local`) or an mpv on a
  paired player — is the transport's; the session never touches a socket
  or a port, and it keeps the host path (`content_url`) as the identity of
  what plays, asking the transport for mpv's locator and for the identity
  of a path mpv reports.

  ## Process lifetime

  mpv's lifetime is the viewer's, not this app's: a backend restart leaves
  the mpv running and the next boot's `SessionRecovery` reattaches to it
  (ADR-023, with the measured lifetime rules in `docs/playback.md`). A
  transport that loses its mpv for now (`{:detached, _}`) stops the
  session's persistence; the session waits `reattach_window_ms` for the
  transport to reattach, then finalises as a stop.

  ## Episode auto-advance (ADR-062)

  A TV episode session appends its successor to the mpv playlist
  (`NextEpisode.resolve/2`), so end-of-episode rolls into the next file
  inside the same mpv — no window teardown, no HDR re-lock. The queueing
  decision runs off mpv's own `playlist-count`/`playlist-pos` properties:
  the successor is appended only while the current entry is the
  playlist's last, which makes the check self-stabilizing and
  reconnect-safe. A `path` change is the advance signal: the session
  closes out the finished episode, re-points its identity at the file now
  playing, and queues the next successor. Quit-on-EOF only ever fires at
  true playlist end — `eof-reached` stays false across mid-playlist
  transitions.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Format
  alias MediaCentaur.Library
  alias MediaCentaur.Library.Progress, as: LibraryProgress

  alias MediaCentaur.Playback.{
    Completion,
    Events,
    LanguageContext,
    LaunchFlags,
    NextEpisode,
    OverrideCapture,
    ProgressBroadcaster,
    SessionRegistry,
    TrackResolver,
    Transport,
    WatchingTracker
  }

  @db_write_interval_ms 10_000
  @reattach_window_ms 60_000

  # Debounce window for capturing user track changes — coalesces rapid
  # keyboard mashing (e.g. #-#-# to cycle audio) into a single capture.
  @track_capture_debounce_ms 3_000

  defstruct [
    :entity_id,
    :player,
    :profile_id,
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
    :transport,
    :position,
    :duration,
    :paused,
    :last_db_write_at,
    :tracker,
    :started_at,
    :reattach_timer,
    reattach_window_ms: @reattach_window_ms,
    state: :starting,
    language_context: nil,
    # mpv `chapter-list` for the loaded file (`[%{"title", "time"}]`), used
    # by `Completion` to complete at the credits boundary rather than
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
    # Every item this session completed (`judge_completion/1`), as
    # `{:movie | :video_object | :extra, id}` or
    # `{:episode, id, season_number, episode_number}`. A chain keeps each
    # episode it finished; `SessionEnded` carries the set.
    completed: MapSet.new()
  ]

  # --- Public API ---

  def start_link(params) do
    GenServer.start_link(__MODULE__, params,
      name: SessionRegistry.via({params.player, params.entity_id})
    )
  end

  def child_spec(params) do
    %{
      id: {__MODULE__, params.player, params.entity_id},
      start: {__MODULE__, :start_link, [params]},
      restart: :temporary
    }
  end

  @doc "Returns a read-only snapshot of the session's current state, by `{player, entity_id}`."
  def get_state(key) do
    case SessionRegistry.lookup(key) do
      nil -> nil
      pid -> GenServer.call(pid, :get_state)
    end
  catch
    # The session ended between the lookup and the call; the registry
    # drops the key a moment after the process.
    :exit, _gone -> nil
  end

  # --- Callbacks ---

  @impl true
  def init(params) do
    Process.flag(:trap_exit, true)

    language_context = LanguageContext.init(params)

    state = %__MODULE__{
      entity_id: params.entity_id,
      player: params.player,
      profile_id: params.profile_id,
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
      transport: params.transport,
      reattach_window_ms: params[:reattach_window_ms] || @reattach_window_ms,
      position: 0.0,
      duration: 0.0,
      paused: false,
      last_db_write_at: System.monotonic_time(:millisecond),
      tracker: WatchingTracker.new(),
      started_at: System.monotonic_time(:millisecond),
      language_context: language_context
    }

    launch = %{
      session_options:
        LaunchFlags.session_options(%{
          profile_id: state.profile_id,
          language_options: LanguageContext.to_mpv_options(language_context.priority_args)
        }),
      content_url: Transport.locator(state.transport, state.content_url),
      start_position: state.start_position,
      profile_id: state.profile_id,
      reattach?: params[:reattach?] || false
    }

    Log.info(
      :playback,
      "session started — #{Path.basename(params.content_url)} via #{Transport.describe(state.transport)}"
    )

    {events, transport} = Transport.open(state.transport, launch)

    case apply_events(events, %{state | transport: transport}) do
      {:noreply, state} -> {:ok, state}
      {:stop, _reason, state} -> {:ok, state, {:continue, :stop}}
    end
  end

  @impl true
  def handle_continue(:stop, state), do: {:stop, :normal, state}

  @impl true
  def handle_call(:get_state, _from, state) do
    reply = %{
      state: state.state,
      now_playing: build_now_playing(state),
      started_at: state.started_at
    }

    {:reply, reply, state}
  end

  @impl true
  # Debounced capture — fires after the user has settled on a track
  # selection. Compares current state against what the resolver chose
  # at episode start; persists an override only if they differ.
  def handle_info(:capture_settled, state) do
    perform_capture(state)
    {:noreply, %{state | capture_timer: nil}}
  end

  # The transport did not come back within its window: the viewing is over.
  def handle_info(:reattach_window_expired, state) do
    if Transport.attached?(state.transport) do
      {:noreply, %{state | reattach_timer: nil}}
    else
      Log.info(:playback, "player did not come back — ending the session")
      {:stop, :normal, finalize(%{state | reattach_timer: nil})}
    end
  end

  # Everything else is the transport's (socket data, port signals, its own
  # timers) or an EXIT the trap absorbs.
  def handle_info(message, state) do
    case Transport.handle_message(state.transport, message) do
      :unhandled -> {:noreply, state}
      {events, transport} -> apply_events(events, %{state | transport: transport})
    end
  end

  @impl true
  # A deliberate stop (`Sessions.stop/2`, reason `:normal`) ends the viewing
  # on the player too. A supervisor shutdown (`:shutdown`) does not: mpv's
  # lifetime is the viewer's, and recovery reattaches on the next boot.
  def terminate(reason, state) do
    final? = state.state == :stopped

    if reason == :normal and not final? and Transport.attached?(state.transport) do
      Transport.send(state.transport, ["quit"])
    end

    finalize(state)
    Transport.close(state.transport, final?)
    :ok
  end

  # --- Transport events ---

  defp apply_events(events, state) do
    Enum.reduce_while(events, {:noreply, state}, fn event, {:noreply, state} ->
      case apply_event(event, state) do
        {:noreply, _state} = reply -> {:cont, reply}
        {:stop, _reason, _state} = reply -> {:halt, reply}
      end
    end)
  end

  defp apply_event({:attached, kind}, state) do
    observe_properties(state.transport)
    Log.info(:playback, "player attached (#{kind})")
    state = cancel_reattach_timer(state)
    broadcast_state_changed(:playing, state)
    {:noreply, %{state | state: :playing}}
  end

  # Discard late messages after finalization.
  defp apply_event({:message, _object}, %{state: :stopped} = state), do: {:noreply, state}

  defp apply_event({:message, object}, state), do: {:noreply, handle_mpv_message(object, state)}

  defp apply_event({:detached, reason}, state) do
    Log.info(
      :playback,
      "player unreachable (#{inspect(reason)}) — waiting #{state.reattach_window_ms}ms"
    )

    state = if state.tracker.actively_watching, do: persist_progress(state), else: state
    state = cancel_reattach_timer(state)
    timer = Process.send_after(self(), :reattach_window_expired, state.reattach_window_ms)
    {:noreply, %{state | reattach_timer: timer}}
  end

  defp apply_event({:closed, {:ok, :ended}}, state), do: {:stop, :normal, finalize(state)}

  defp apply_event({:closed, {:error, reason, message}}, state) do
    broadcast_playback_failed(state, reason, message)
    {:stop, :normal, finalize(state)}
  end

  defp cancel_reattach_timer(%{reattach_timer: nil} = state), do: state

  defp cancel_reattach_timer(state) do
    Process.cancel_timer(state.reattach_timer)
    %{state | reattach_timer: nil}
  end

  # --- Idempotent Finalization ---
  # Guard prevents double-finalize on already-stopped sessions.

  defp finalize(%{state: session_state} = session) when session_state in [:playing, :paused] do
    session = if session.tracker.actively_watching, do: persist_progress(session), else: session

    cond do
      # Extra playback — broadcast extra progress update
      session.extra_id ->
        profile_id = session.profile_id
        entity_id = session.entity_id
        extra_id = session.extra_id

        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          ProgressBroadcaster.broadcast_extra(profile_id, entity_id, extra_id)
        end)

      # Entity/episode/movie playback — broadcast entity progress update
      session.movie_id || session.episode_id || session.video_object_id ->
        profile_id = session.profile_id
        entity_id = session.entity_id

        Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
          # Explicit nil: this is the end-of-playback summary refresh. The
          # per-tick broadcast in persist_progress/1 already carried the
          # changed playable_item_id, so there is no single record to
          # report here.
          ProgressBroadcaster.broadcast(profile_id, entity_id, nil)
        end)

      # No progress tracking (shouldn't happen, but safe fallback)
      true ->
        :ok
    end

    broadcast_state_changed(:stopped, session)
    # After `:stopped`, on the same topic from the same process: a
    # subscriber has dropped the entity from its playing set before it
    # reads what the session completed.
    Events.broadcast(session_ended(session))
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

    state = if paused and state.tracker.actively_watching, do: persist_progress(state), else: state
    broadcast_state_changed(new_state, state)

    state
  end

  defp handle_mpv_message(
         %{"event" => "property-change", "name" => "eof-reached", "data" => true},
         state
       ) do
    Log.info(:playback, "reached end of file")
    state = finalize(state)
    Transport.send(state.transport, ["quit"])
    state
  end

  defp handle_mpv_message(%{"event" => "end-file"}, %{pending_next: nil} = state) do
    finalize(state)
  end

  # Mid-chain end-file: mpv is advancing into the queued entry, not
  # exiting. Save the outgoing episode's progress now, while `position`
  # and `chapters` still describe the finished file — the new file's
  # property events would clobber them before the `path` change lands.
  # If this end-file is actually a quit, the transport's close still
  # finalizes the session moments later.
  defp handle_mpv_message(%{"event" => "end-file"}, state) do
    if state.tracker.actively_watching, do: persist_progress(state), else: state
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
  # we launched. Only a change to a different file is an advance. The
  # transport maps what mpv reports back to the host path, the identity
  # this session compares.
  defp handle_mpv_message(%{"event" => "property-change", "name" => "path", "data" => path}, state)
       when is_binary(path) do
    case Transport.identify(state.transport, path) do
      nil -> advance_to(state, :unknown, path)
      content_url when content_url == state.content_url -> state
      content_url -> advance_to(state, {:ok, content_url}, path)
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
    if queue_next?(state) do
      queue_next(state)
    else
      state
    end
  end

  @doc """
  Whether the successor should be appended now (ADR-062): an episode
  session with an attached transport, nothing already queued, the current
  entry the playlist's last. Declining auto-advance needs no state here —
  quitting the player ends the session, queued entry and all.
  """
  @spec queue_next?(%__MODULE__{}) :: boolean()
  def queue_next?(state) do
    is_nil(state.pending_next) and not is_nil(state.episode_id) and
      Transport.attached?(state.transport) and
      state.playlist_count - state.playlist_pos == 1
  end

  defp queue_next(state) do
    case NextEpisode.resolve(state.profile_id, state.episode_id) do
      {:ok, item} ->
        located = %{item | content_url: Transport.locator(state.transport, item.content_url)}
        Transport.send(state.transport, NextEpisode.loadfile_command(located))

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
  # path matches; otherwise it is re-derived from the host path (the
  # ADR-023 discipline — covers entries queued before a backend restart).
  # The outgoing episode's final progress was persisted at its end-file.
  defp advance_to(state, {:ok, content_url}, reported_path) do
    identity =
      case state.pending_next do
        %{content_url: ^content_url} = item -> {:ok, item}
        _ -> NextEpisode.identify(state.entity_id, content_url)
      end

    case identity do
      {:ok, item} ->
        Log.info(
          :playback,
          "advanced to S#{item.season_number}E#{item.episode_number} — #{Path.basename(content_url)}"
        )

        state = reset_for_file(state, content_url, %{episode_id: item.episode_id}, item)
        broadcast_state_changed(state.state, state)
        maybe_queue_next(state)

      :none ->
        advance_to(state, :unknown, reported_path)
    end
  end

  # A file this session can't attribute (user loaded something into mpv by
  # hand, or the library changed underneath). Stop attributing progress
  # rather than corrupting the old episode's.
  defp advance_to(state, :unknown, reported_path) do
    Log.warning(
      :playback,
      "playlist advanced to unrecognized file — #{Path.basename(reported_path)}; progress attribution stops"
    )

    reset_for_file(
      state,
      reported_path,
      %{episode_id: nil, movie_id: nil, video_object_id: nil},
      %{season_number: nil, episode_number: nil, episode_name: nil}
    )
  end

  # Pure apart from cancelling the capture timer; public so the test can
  # pin that an advance keeps the profile the session was started for.
  @doc false
  def reset_for_file(state, path, fk_fields, item) do
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
          Transport.send(state.transport, ["set_property", "sid", sid])
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
    # our `slang` before subtitle tracks demux, so an event-time snapshot
    # can read "no subs" while the eng sub is in fact selected. Deriving
    # here is what stops the per-series `subtitles_off` poison — see
    # `LanguageContext.current_selection/4`.
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
        persist_track_override(state, attrs)
    end
  end

  defp persist_track_override(state, attrs) do
    %{owner_type: owner_type, owner_id: owner_id} = state.language_context

    case Library.MediaTrackOverrides.upsert(state.profile_id, owner_type, owner_id, attrs) do
      {:ok, _override} ->
        Log.info(
          :playback,
          "captured track override (#{owner_type}=#{Format.short_id(owner_id)}) — #{inspect(attrs)}"
        )

        Events.broadcast(%Events.TrackOverrideChanged{
          profile_id: state.profile_id,
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
      %{persist_progress(state) | last_db_write_at: now}
    else
      state
    end
  end

  # --- Progress Persistence ---

  # Judges completion here, in the session, so the session knows what it
  # completed; the write itself runs in a task.
  defp persist_progress(state) do
    {reason, state} = judge_completion(state)
    write_progress(state, reason)
    state
  end

  defp write_progress(%{extra_id: extra_id} = state, reason) when not is_nil(extra_id) do
    persist_extra_progress(state, reason)
  end

  defp write_progress(%{movie_id: nil, episode_id: nil, video_object_id: nil}, _reason), do: :ok

  defp write_progress(state, reason), do: persist_entity_progress(state, reason)

  @doc """
  Judges the saved position against `Completion.reason/3`; a complete
  one adds the playing item (`current_item/1`) to `completed`. Returns
  the reason (nil while incomplete) with the state.
  """
  @spec judge_completion(%__MODULE__{}) :: {String.t() | nil, %__MODULE__{}}
  def judge_completion(state) do
    reason = Completion.reason(saveable_position(state), state.duration, state.chapters)

    case {reason, current_item(state)} do
      {nil, _item} -> {nil, state}
      {reason, nil} -> {reason, state}
      {reason, item} -> {reason, %{state | completed: MapSet.put(state.completed, item)}}
    end
  end

  @doc "The `SessionEnded` event for this session."
  @spec session_ended(%__MODULE__{}) :: Events.SessionEnded.t()
  def session_ended(state) do
    %Events.SessionEnded{
      entity_id: state.entity_id,
      player: state.player,
      profile_id: state.profile_id,
      completed: state.completed
    }
  end

  defp current_item(%{extra_id: id}) when not is_nil(id), do: {:extra, id}
  defp current_item(%{movie_id: id}) when not is_nil(id), do: {:movie, id}

  defp current_item(%{episode_id: id} = state) when not is_nil(id),
    do: {:episode, id, state.season_number, state.episode_number}

  defp current_item(%{video_object_id: id}) when not is_nil(id), do: {:video_object, id}
  defp current_item(_state), do: nil

  defp saveable_position(state), do: state.tracker.saveable_position || state.position

  defp persist_extra_progress(state, reason) do
    saveable = saveable_position(state)
    duration = state.duration

    params = %{
      profile_id: state.profile_id,
      extra_id: state.extra_id,
      entity_id: state.entity_id,
      position_seconds: saveable,
      duration_seconds: duration
    }

    profile_id = state.profile_id
    entity_id = state.entity_id
    extra_id = state.extra_id

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      case MediaCentaur.Library.ProgressRecords.find_or_create_for_extra(params) do
        {:ok, record} ->
          Log.info(
            :playback,
            "saved extra progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
          )

          maybe_mark_extra_completed(record, reason)
          ProgressBroadcaster.broadcast_extra(profile_id, entity_id, extra_id)

        {:error, reason} ->
          Log.warning(:playback, "failed to save extra progress — #{inspect(reason)}")
      end
    end)
  end

  defp persist_entity_progress(state, reason) do
    saveable = saveable_position(state)
    duration = state.duration

    params =
      %{
        position_seconds: saveable,
        duration_seconds: duration
      }
      |> maybe_put(:movie_id, state.movie_id)
      |> maybe_put(:episode_id, state.episode_id)
      |> maybe_put(:video_object_id, state.video_object_id)

    profile_id = state.profile_id
    entity_id = state.entity_id

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      case resolve_or_create_playable_item_id(params) do
        {:ok, playable_item_id} ->
          # Hot-path write: lands in the Library.Progress in-memory
          # table in microseconds; the debounced flush persists to
          # `library_watch_progress` on the next interval (default 5s)
          # or synchronously on clean shutdown.
          :ok = LibraryProgress.record(profile_id, playable_item_id, saveable, duration)

          Log.info(
            :playback,
            "saved progress — #{Format.format_seconds(saveable)} of #{Format.format_seconds(duration)}"
          )

          maybe_mark_completed(profile_id, playable_item_id, reason)
          # The rich `%EntityProgressUpdated{}` event carries the changed
          # record, so the detail modal's in-memory merge flips a
          # per-episode badge live rather than on a full remount.
          ProgressBroadcaster.broadcast(profile_id, entity_id, playable_item_id)

        {:error, reason} ->
          Log.warning(:playback, "failed to save progress — #{inspect(reason)}")
      end
    end)
  end

  # Resolves the canonical PlayableItem for the session's container FK
  # without writing any WatchProgress row — that's the Progress worker's job.
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

  defp maybe_mark_completed(_profile_id, _playable_item_id, nil), do: :ok

  defp maybe_mark_completed(profile_id, playable_item_id, reason) do
    case LibraryProgress.get(profile_id, playable_item_id) do
      %{completed: true} ->
        :ok

      _ ->
        Log.info(:playback, "marked completed — #{reason}")
        :ok = LibraryProgress.complete(profile_id, playable_item_id)
    end
  end

  defp maybe_mark_extra_completed(_record, nil), do: :ok
  defp maybe_mark_extra_completed(%{completed: true}, _reason), do: :ok

  defp maybe_mark_extra_completed(record, reason) do
    Log.info(:playback, "extra marked completed — #{reason}")

    case MediaCentaur.Library.ProgressRecords.mark_completed(record) do
      {:ok, _} -> :ok
      {:error, error} -> Log.warning(:playback, "failed to mark extra completed — #{inspect(error)}")
    end
  end

  # --- PubSub Broadcasting ---

  defp broadcast_state_changed(new_state, session) do
    now_playing = build_now_playing_for_broadcast(new_state, session)

    Events.broadcast(%Events.PlaybackStateChanged{
      entity_id: session.entity_id,
      player: session.player,
      profile_id: session.profile_id,
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

  defp broadcast_playback_failed(session, reason, message) do
    Events.broadcast(%Events.PlaybackFailed{
      entity_id: session.entity_id,
      player: session.player,
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

  # --- Observation ---

  defp observe_properties(transport) do
    Transport.send(transport, ["observe_property", 1, "time-pos"])
    Transport.send(transport, ["observe_property", 2, "duration"])
    Transport.send(transport, ["observe_property", 3, "pause"])
    Transport.send(transport, ["observe_property", 4, "eof-reached"])
    Transport.send(transport, ["observe_property", 5, "track-list"])
    Transport.send(transport, ["observe_property", 6, "aid"])
    Transport.send(transport, ["observe_property", 7, "sid"])
    Transport.send(transport, ["observe_property", 8, "chapter-list"])
    Transport.send(transport, ["observe_property", 9, "playlist-count"])
    Transport.send(transport, ["observe_property", 10, "playlist-pos"])
    Transport.send(transport, ["observe_property", 11, "path"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
