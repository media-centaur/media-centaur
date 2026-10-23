defmodule MediaCentaur.Playback.MpvSession do
  @moduledoc """
  Per-session GenServer observing one mpv through a `Playback.Transport`.

  Each session tracks one entity's *viewing chain*, identified by the
  entity id of its `Playback.Entry` (what plays now: the file, its library
  identity, where it started), on one **player** (`:host`, or a paired
  player's id), and holds the profile it was started for (`profile_id`,
  ADR-078) for its whole life —
  progress, track memory and every event it broadcasts are that profile's,
  and a switch mid-film does not re-home them. Every event names the
  player too. Sessions register in `SessionRegistry` by
  `{player, entity_id}` for lookup and enumeration.

  This is an observation-only tracker — the user controls mpv directly,
  or, on a player that draws nothing, through the host's page: a reader
  sends a `Playback.Command` (`command/2`) and the session renders it to
  IPC, the one writer to the player. Every reader sees the viewing as one
  `Playback.Viewing`, carried on `PlaybackStateChanged.now_playing` and
  streamed on the player's viewing topic (`Playback.subscribe_viewing/1`):
  on attach, on every discrete change (pause, chapter, tracks, the
  subtitle line, the prompt) and on position at most once a second.
  The session observes position/duration/pause/eof over IPC, persists
  watch progress, and broadcasts state changes via PubSub. How the mpv is
  reached — a process the host spawns (`Transport.Local`) or an mpv on a
  paired player — is the transport's; the session never touches a socket
  or a port, and it keeps the host path (the entry's `content_url`) as the
  identity of what plays, asking the transport for mpv's locator and for
  the identity of a path mpv reports.

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
  closes out the finished episode, replaces its entry with the file now
  playing, and queues the next successor. Quit-on-EOF only ever fires at
  true playlist end — `eof-reached` stays false across mid-playlist
  transitions.
  """
  use GenServer
  require MediaCentaur.Log, as: Log

  alias MediaCentaur.Playback.{
    Chain,
    Command,
    Entry,
    Events,
    LanguageContext,
    LaunchFlags,
    MpvProperties,
    ProgressWriter,
    SessionRegistry,
    Transport,
    Viewing,
    WatchingTracker
  }

  @db_write_interval_ms 10_000
  @reattach_window_ms 60_000

  @track_capture_debounce_ms 3_000

  defstruct [
    # What plays now (`Playback.Entry`); replaced whole by an advance.
    :entry,
    :player,
    :profile_id,
    :transport,
    :last_db_write_at,
    :tracker,
    :started_at,
    :reattach_timer,
    reattach_window_ms: @reattach_window_ms,
    state: :starting,
    # The track policy (`Playback.LanguageContext`).
    language_context: nil,
    # What mpv last reported (`Playback.MpvProperties`).
    properties: %MpvProperties{},
    capture_timer: nil,
    # The successor's entry, appended to the mpv playlist and not yet
    # reached (ADR-062). `nil` while nothing is queued — chain end,
    # auto-play off, or a non-episode session.
    pending_next: nil,
    # Every `Entry.item/1` this session completed (`judge_completion/1`).
    # A chain keeps each episode it finished; `SessionEnded` carries the set.
    completed: MapSet.new(),
    # When the viewing was last streamed for a position tick; nil before
    # the first. Discrete changes stream at once and leave this alone.
    last_position_stream_at: nil
  ]

  @viewing_position_interval_ms 1_000
  @file_unknown_message "Media Centaur hasn't indexed this file yet."

  # --- Public API ---

  def start_link(params) do
    GenServer.start_link(__MODULE__, params,
      name: SessionRegistry.via({params.player, params.entry.entity_id})
    )
  end

  def child_spec(params) do
    %{
      id: {__MODULE__, params.player, params.entry.entity_id},
      start: {__MODULE__, :start_link, [params]},
      restart: :temporary
    }
  end

  @doc "Sends a reader's `Playback.Command` to the session at `{player, entity_id}`; refused when none runs."
  @spec command(SessionRegistry.key(), Command.t()) :: :ok | {:error, :no_session}
  def command(key, command) do
    case SessionRegistry.lookup(key) do
      nil -> {:error, :no_session}
      pid -> GenServer.cast(pid, {:command, command})
    end
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

    %Entry{} = entry = params.entry

    state = %__MODULE__{
      entry: entry,
      player: params.player,
      profile_id: params.profile_id,
      transport: params.transport,
      reattach_window_ms: params[:reattach_window_ms] || @reattach_window_ms,
      last_db_write_at: System.monotonic_time(:millisecond),
      tracker: WatchingTracker.new(),
      started_at: System.monotonic_time(:millisecond),
      language_context: LanguageContext.init(params.profile_id, entry)
    }

    {events, state} =
      case Transport.locator(state.transport, entry.content_url) do
        {:ok, locator} ->
          open(state, locator, params[:reattach?] || false)

        # The player could not be told what to load (a remote player with
        # no presence row for the file): the viewing fails before anything
        # loads, as a startup failure does.
        {:error, reason} ->
          Log.warning(
            :playback,
            "cannot name #{Path.basename(entry.content_url)} to #{Transport.describe(state.transport)} (#{reason})"
          )

          {[{:closed, {:error, :file_unknown, @file_unknown_message}}], state}
      end

    case apply_events(events, state) do
      {:noreply, state} -> {:ok, state}
      {:stop, _reason, state} -> {:ok, state, {:continue, :stop}}
    end
  end

  defp open(state, locator, reattach?) do
    launch = %{
      session_options:
        LaunchFlags.session_options(%{
          profile_id: state.profile_id,
          language_options: LanguageContext.to_mpv_options(state.language_context.priority_args)
        }),
      content_url: locator,
      start_position: state.entry.start_position,
      profile_id: state.profile_id,
      reattach?: reattach?
    }

    Log.info(
      :playback,
      "session started — #{Path.basename(state.entry.content_url)} via #{Transport.describe(state.transport)}"
    )

    {events, transport} = Transport.open(state.transport, launch)
    {events, %{state | transport: transport}}
  end

  @impl true
  def handle_continue(:stop, state), do: {:stop, :normal, state}

  @impl true
  def handle_call(:get_state, _from, state) do
    reply = %{
      state: state.state,
      now_playing: Viewing.from_session(state),
      started_at: state.started_at
    }

    {:reply, reply, state}
  end

  @impl true
  # A reader's command, bounded to the file, rendered against the viewing's
  # current prompt and sent through the transport; a command with nothing
  # to send is dropped.
  def handle_cast({:command, command}, state) do
    with bounded when bounded != nil <-
           Command.within(command, state.properties.position, state.properties.duration),
         ipc when ipc != nil <- Command.ipc(bounded, Viewing.from_session(state).prompt) do
      Transport.send(state.transport, ipc)
    end

    {:noreply, state}
  end

  @impl true
  # Debounced capture — fires after the user has settled on a track
  # selection. Compares current state against what the resolver chose
  # at episode start; persists an override only if they differ.
  def handle_info(:capture_settled, state) do
    if LanguageContext.captures?(state.language_context) do
      LanguageContext.capture(state.language_context, state.profile_id, state.properties)
    end

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
    {:noreply, stream_viewing(%{state | state: :playing})}
  end

  # Discard late messages after finalization.
  defp apply_event({:message, _object}, %{state: :stopped} = state), do: {:noreply, state}

  defp apply_event({:message, object}, state),
    do: {:noreply, object |> handle_mpv_message(state) |> maybe_stream_viewing(object)}

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

    ProgressWriter.broadcast_end(session.profile_id, session.entry)

    broadcast_state_changed(:stopped, session)
    # After `:stopped`, on the same topic from the same process: a
    # subscriber has dropped the entity from its playing set before it
    # reads what the session completed.
    Events.broadcast(session_ended(session))

    Events.broadcast_viewing_ended(%Events.ViewingEnded{
      player: session.player,
      entity_id: session.entry.entity_id
    })

    %{session | state: :stopped}
  end

  defp finalize(session), do: %{session | state: :stopped}

  # --- MPV Message Handling ---

  # Every property change is folded into the mirror first; the session then
  # reacts to the ones that move it (`react/3`). mpv omits `data` for a
  # property with no value (a `sub-text` between lines).
  defp handle_mpv_message(%{"event" => "property-change", "name" => name} = message, state) do
    data = message["data"]
    react(name, data, %{state | properties: MpvProperties.apply(state.properties, name, data)})
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

  defp handle_mpv_message(_message, state), do: state

  # --- Reactions to a property change (the mirror already holds it) ---

  defp react("time-pos", position, state) when is_number(position) do
    now = System.monotonic_time(:millisecond)
    tracker = WatchingTracker.update(state.tracker, position, now)

    if tracker.actively_watching and not state.tracker.actively_watching do
      Log.info(:playback, "actively watching")
    end

    maybe_persist(%{state | tracker: tracker})
  end

  defp react("pause", paused, state) when is_boolean(paused) do
    new_state = if paused, do: :paused, else: :playing
    Log.info(:playback, if(paused, do: "paused", else: "resumed"))
    state = %{state | state: new_state}

    state = if paused and state.tracker.actively_watching, do: persist_progress(state), else: state
    broadcast_state_changed(new_state, state)

    state
  end

  defp react("eof-reached", true, state) do
    Log.info(:playback, "reached end of file")
    state = finalize(state)
    Transport.send(state.transport, ["quit"])
    state
  end

  defp react("track-list", tracks, state) when is_list(tracks) do
    {language_context, commands} =
      LanguageContext.on_track_list(
        state.language_context,
        state.properties,
        Transport.draws_subtitles?(state.transport)
      )

    Enum.each(commands, &Transport.send(state.transport, &1))
    %{state | language_context: language_context}
  end

  defp react(playlist, count, state)
       when playlist in ["playlist-count", "playlist-pos"] and is_integer(count),
       do: maybe_queue_next(state)

  # `path` is nil between files; the initial observation echoes the file
  # we launched. Only a change to a different file is an advance. The
  # transport maps what mpv reports back to the host path, the identity
  # this session compares.
  defp react("path", path, state) when is_binary(path) do
    case Transport.identify(state.transport, path) do
      nil -> advance_to(state, :unknown, path)
      content_url when content_url == state.entry.content_url -> state
      content_url -> advance_to(state, {:ok, content_url}, path)
    end
  end

  defp react(track, _id, state) when track in ["aid", "sid"], do: schedule_capture(state)

  defp react(_name, _data, state), do: state

  # --- Episode auto-advance (ADR-062, `Chain`) ---

  # Runs off every playlist-count/playlist-pos change and after each
  # advance; all other states are no-ops, so the check is idempotent.
  defp maybe_queue_next(state) do
    if Chain.queue_next?(state.pending_next, state.entry, state.properties, state.transport) do
      queue_next(state)
    else
      state
    end
  end

  defp queue_next(state) do
    case Chain.successor(state.profile_id, state.entry, state.transport) do
      {:ok, entry, ipc} ->
        Transport.send(state.transport, ipc)

        Log.info(
          :playback,
          "queued next episode — S#{entry.season_number}E#{entry.episode_number} #{Path.basename(entry.content_url)}"
        )

        %{state | pending_next: entry}

      :none ->
        state

      # The successor exists but this player cannot be told to load it: the
      # chain ends here, as it does for a successor with no file.
      {:error, reason} ->
        Log.warning(
          :playback,
          "cannot queue the next episode on #{Transport.describe(state.transport)} (#{reason})"
        )

        state
    end
  end

  # A playlist advance landed on a new file: the session's entry becomes
  # the episode now playing. The outgoing episode's final progress was
  # persisted at its end-file.
  defp advance_to(state, {:ok, content_url}, reported_path) do
    case Chain.advance(state.pending_next, state.entry.entity_id, content_url) do
      {:ok, entry} ->
        Log.info(
          :playback,
          "advanced to S#{entry.season_number}E#{entry.episode_number} — #{Path.basename(content_url)}"
        )

        state = reset_for_file(state, entry)
        broadcast_state_changed(state.state, state)
        state |> maybe_queue_next() |> stream_viewing()

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

    reset_for_file(state, Entry.unattributed(state.entry, reported_path))
  end

  # The session's per-file reset for an advance to `entry`. Pure apart from
  # cancelling the capture timer; public so the test can pin that an
  # advance keeps the profile the session was started for.
  @doc false
  def reset_for_file(state, %Entry{} = entry) do
    if state.capture_timer, do: Process.cancel_timer(state.capture_timer)

    %{
      state
      | entry: entry,
        properties: MpvProperties.reset_for_file(state.properties),
        tracker: WatchingTracker.new(),
        language_context: LanguageContext.reset_for_file(state.language_context),
        capture_timer: nil,
        pending_next: nil,
        last_db_write_at: System.monotonic_time(:millisecond),
        state: if(state.properties.paused, do: :paused, else: :playing)
    }
  end

  # --- Track override capture (`LanguageContext`) ---

  # No capture for an entry without an override owner (extras, video
  # objects) or before the resolver has chosen — skip scheduling rather
  # than computing-and-discarding to avoid spurious timer churn. The
  # debounce coalesces rapid keyboard mashing (#-#-# to cycle audio) into
  # a single capture.
  defp schedule_capture(state) do
    if LanguageContext.captures?(state.language_context) do
      if state.capture_timer, do: Process.cancel_timer(state.capture_timer)
      timer = Process.send_after(self(), :capture_settled, @track_capture_debounce_ms)
      %{state | capture_timer: timer}
    else
      state
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

  # --- Progress Persistence (`ProgressWriter`) ---

  # The session judges completion so it knows what it completed; the
  # write runs in a task.
  defp persist_progress(state) do
    {reason, completed} =
      ProgressWriter.judge(state.completed, state.entry, state.properties, state.tracker)

    ProgressWriter.persist(state.profile_id, state.entry, state.properties, state.tracker, reason)
    %{state | completed: completed}
  end

  @doc "The `SessionEnded` event for this session."
  @spec session_ended(%__MODULE__{}) :: Events.SessionEnded.t()
  def session_ended(state) do
    %Events.SessionEnded{
      entity_id: state.entry.entity_id,
      player: state.player,
      profile_id: state.profile_id,
      completed: state.completed
    }
  end

  # --- PubSub Broadcasting ---

  defp broadcast_state_changed(new_state, session) do
    now_playing = build_now_playing_for_broadcast(new_state, session)

    Events.broadcast(%Events.PlaybackStateChanged{
      entity_id: session.entry.entity_id,
      player: session.player,
      profile_id: session.profile_id,
      state: new_state,
      now_playing: now_playing,
      started_at: session.started_at
    })
  end

  defp build_now_playing_for_broadcast(new_state, session) when new_state in [:playing, :paused] do
    Viewing.from_session(session)
  end

  defp build_now_playing_for_broadcast(_new_state, _session), do: nil

  # --- The viewing stream ---

  # A position tick streams at most once a second; every other property the
  # page draws streams as it changes. Nothing streams after the end.
  @streamed_properties ~w(pause duration chapter chapter-list sub-text track-list aid sid playlist-count playlist-pos)

  defp maybe_stream_viewing(%{state: :stopped} = state, _object), do: state

  defp maybe_stream_viewing(state, %{"event" => "property-change", "name" => "time-pos"}) do
    now = System.monotonic_time(:millisecond)

    if is_nil(state.last_position_stream_at) or
         now - state.last_position_stream_at >= @viewing_position_interval_ms do
      stream_viewing(%{state | last_position_stream_at: now})
    else
      state
    end
  end

  defp maybe_stream_viewing(state, %{"event" => "property-change", "name" => name})
       when name in @streamed_properties, do: stream_viewing(state)

  defp maybe_stream_viewing(state, _object), do: state

  defp stream_viewing(%{state: :stopped} = state), do: state

  defp stream_viewing(state) do
    Events.broadcast_viewing(Viewing.from_session(state))
    state
  end

  # The payload is the web formatter's flat contract
  # (`LibraryFormatters.playback_failed_flash/1`), built from the entry here.
  defp broadcast_playback_failed(session, reason, message) do
    %Entry{} = entry = session.entry

    Events.broadcast(%Events.PlaybackFailed{
      entity_id: entry.entity_id,
      player: session.player,
      reason: reason,
      payload: %{
        message: message,
        entity_name: entry.entity_name,
        season_number: entry.season_number,
        episode_number: entry.episode_number,
        episode_name: entry.episode_name,
        content_url: entry.content_url
      }
    })
  end

  # --- Observation ---

  defp observe_properties(transport) do
    for {name, id} <- Enum.with_index(MpvProperties.observed(), 1) do
      Transport.send(transport, ["observe_property", id, name])
    end
  end
end
