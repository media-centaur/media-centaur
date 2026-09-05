defmodule MediaCentaurWeb.StatusLive do
  @moduledoc """
  Operational status page at `/status`.

  Surfaces the Subsystem Health Board, pending review count, pipeline health,
  watcher state, storage metrics, external integrations, and active playback
  summary. The library itself lives at `/`; this page is the
  developer/operator view.
  """
  use MediaCentaurWeb, :live_view

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.HealthComponents

  alias MediaCentaur.Social
  alias MediaCentaur.Social.Connections
  alias MediaCentaur.Recommendations
  alias MediaCentaur.Settings.Config
  alias MediaCentaur.{ErrorReports, Playback, SelfUpdate, Status, Topics}
  alias MediaCentaur.SelfUpdate.Changelog
  alias MediaCentaur.Version
  alias MediaCentaurWeb.StatusLive.ActivityWidgets
  alias MediaCentaurWeb.StatusLive.HealthBoard
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.Pipeline.Image, as: ImagePipeline
  alias MediaCentaur.Watcher
  alias MediaCentaur.WatchHistory.Views.PlaybackActivity
  alias MediaCentaurWeb.StatusLive.ReportModal
  alias MediaCentaurWeb.Components.IssueView
  alias MediaCentaur.Capabilities
  alias MediaCentaur.Acquisition
  alias MediaCentaur.Acquisition.Pursuits.Throughput
  alias MediaCentaur.Downloads.QueueMonitor
  alias MediaCentaur.Runtime.Vitals

  @vitals_refresh_ms 5 * 60 * 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Status")

    if connected?(socket) do
      Watcher.Supervisor.subscribe()
      Playback.subscribe()
      ErrorReports.subscribe()
      SelfUpdate.subscribe()
      SelfUpdate.subscribe_progress()
      MediaCentaur.WatchHistory.subscribe()
      Acquisition.subscribe_queue()
      Capabilities.subscribe_changes()
      Status.Views.subscribe()
      Social.subscribe_connections()

      # Visiting /status marks auto-detected incidents as seen, clearing
      # the discovery badge on the Status nav item. The web layer owns
      # the diagnostics_seen_at timestamp (DiagnosticsBadge), so the
      # ErrorReports context stays free of any Settings dependency.
      MediaCentaurWeb.DiagnosticsBadge.mark_seen()

      Topics.subscribe(Topics.pipeline_stats())
      Process.send_after(self(), :refresh_vitals, @vitals_refresh_ms)
    end

    {:ok,
     assign(socket,
       loaded?: false,
       pipeline_concurrency: MediaCentaur.Pipeline.Discovery.processor_concurrency(),
       image_pipeline_concurrency: 8,
       show_report_modal: false,
       report_payload: nil,
       report_snapshot: nil,
       self_update_apply_progress: nil
     )}
  end

  # Snapshot of the self-update subsystem for the Updates Activity widget.
  # `last_check_at` and `upgrade_history` (both Settings reads) are captured into
  # assigns here — `last_check_at` refreshes on `{:check_complete, …}`, history
  # changes only at boot — because they change rarely, not because the render
  # path must avoid DB reads.
  #
  # Tombstone: this used to defer the read "to keep `activity_bundle/1` free of
  # DB queries on the render path (UIDR-012)." That rule is retired — ADR-051
  # supersedes the "no DB on the render/mount path" gate for local reads (it
  # caused first-paint flashes, and a local query is one user's millisecond).
  # Don't re-add a "keep the render path DB-free" gate here.
  defp assign_self_update(socket) do
    {status, release} = SelfUpdate.last_known_status()
    %{phase: phase} = SelfUpdate.current_status()

    assign(socket,
      self_update_status: status,
      self_update_release: release,
      self_update_last_check_at: SelfUpdate.last_check_at(),
      self_update_history: recent_update_history(),
      self_update_apply_phase: if(phase != :idle, do: phase)
    )
  end

  # Recent upgrade history (newest-first, capped) with each version's CHANGELOG
  # notes attached for the Updates tile's inline-expandable detail. Versions with
  # no changelog match carry notes_body: nil and render as a plain row.
  defp recent_update_history do
    SelfUpdate.upgrade_history()
    |> Enum.take(5)
    |> Enum.map(fn entry -> Map.put(entry, :notes_body, Changelog.for_version(entry.version)) end)
  end

  # Keeps the board view-models in sync with the current `error_buckets`.
  defp assign_board(socket) do
    assign(socket, board: HealthBoard.build_board(socket.assigns.error_buckets))
  end

  # The full page state loads synchronously in handle_params — un-gated, so
  # the dead render is already complete and the connected mount repeats the
  # same cheap reads (ADR-051; do NOT re-add a `connected?` gate here, that
  # is exactly the first-paint flash this shape removes). The two slices
  # that are genuinely expensive — the library overview's per-image disk
  # check and the storage `df` probes — are NOT computed here: they come
  # from the `Status.Views` projections as ETS lookups, refreshed off the
  # navigation path by their Cache.Workers.
  defp ensure_loaded(%{assigns: %{loaded?: true}} = socket), do: socket

  defp ensure_loaded(socket) do
    socket
    |> assign(loaded?: true)
    |> assign(error_buckets: ErrorReports.list_buckets())
    |> assign_board()
    |> assign(pipeline_stats: Stats.get_snapshot())
    |> assign(image_pipeline_stats: ImagePipeline.Stats.get_snapshot())
    |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
    |> assign(image_dir_statuses: MediaCentaur.Watcher.Supervisor.image_dir_statuses())
    |> assign(scan_stats: MediaCentaur.Watcher.Supervisor.scan_stats())
    |> assign(config: load_config())
    |> assign(rate_limiter: fetch_rate_limiter())
    |> assign(http_stats: MediaCentaur.HttpClient.Stats.snapshot())
    |> assign(metadata_stats: MediaCentaur.TMDB.MetadataStats.snapshot())
    |> assign(retry_status: fetch_retry_status())
    |> assign(playback: build_playback_state())
    |> assign(playback_activity: PlaybackActivity.snapshot())
    |> assign(system_vitals: Vitals.snapshot())
    |> assign(acquisition_activity: build_acquisition_activity())
    |> assign(retention_by_subsystem: MediaCentaur.Retention.status_by_subsystem())
    |> update(:badges, &%{&1 | diagnostics_unseen: 0})
    |> assign(overview: Status.Views.overview())
    |> assign_storage_snapshot(Status.Views.storage())
    |> assign_self_update()
    |> assign_social()
  end

  # Snapshot of the friend network for the Social Activity widget:
  # aggregates only (Settings → Social and the Friends tab own the lists). `Recommendations.counts/0`
  # is two aggregate queries — cheaper than loading every row just to
  # count and diff them.
  defp assign_social(socket) do
    counts = Recommendations.counts()

    assign(socket,
      relay_status: relay_status(),
      friend_count: length(Social.list_friends()),
      sent_count: counts.sent,
      received_count: counts.received,
      last_received_at: counts.last_received_at
    )
  end

  # The configured relays are the relay rows, not the connection owner's
  # map: the owner reconciles to those rows, but it is not running in
  # every environment, and a widget that read only its map would report
  # "no relays configured" when the truth is "no connections yet". A relay
  # nothing has been heard from yet takes the blank (`:connecting`) entry.
  defp relay_status do
    live = Connections.status()
    Map.new(Social.list_relays(), &{&1.url, Map.get(live, &1.url, Connections.blank_entry())})
  end

  defp assign_storage_snapshot(socket, snapshot) do
    assign(socket,
      storage_drives: snapshot.drives,
      at_risk_summary: snapshot.at_risk,
      dir_health: snapshot.dir_health
    )
  end

  # Both the subsystem drill-in and the incident issue view are URL-driven
  # (deep-linkable): the URL is the single source of truth, events only
  # `push_patch/2`, and `handle_params/3` derives the open state from it. The
  # incident is layered view-state on top of the page (not a distinct
  # resource), so it composes as a second query param rather than a path
  # segment — `/status?subsystem=acquisition&incident=<fingerprint>`.
  @impl true
  def handle_params(params, _uri, socket) do
    socket = ensure_loaded(socket)

    {:noreply,
     assign(socket,
       selected_subsystem: parse_subsystem(params),
       selected_incident: parse_incident(params, socket.assigns.error_buckets)
     )}
  end

  defp parse_subsystem(%{"subsystem" => raw}) do
    atom = safe_existing_atom(raw)
    if atom in HealthBoard.board_subsystems(), do: atom
  end

  defp parse_subsystem(_params), do: nil

  # Resolve the open incident from the currently-displayed buckets. On a cold
  # deep-link this is the cache snapshot loaded in mount; after an optimistic
  # dismiss it reflects the local eviction, so a just-dismissed fingerprint
  # resolves to nil (the modal closes) rather than re-opening from the cache.
  defp parse_incident(%{"incident" => fingerprint}, error_buckets) when is_binary(fingerprint) do
    Enum.find(error_buckets, &(&1.fingerprint == fingerprint))
  end

  defp parse_incident(_params, _error_buckets), do: nil

  # Builds the `/status` URL preserving whichever of subsystem / incident are
  # set; both are query params, nils are dropped.
  defp status_path(subsystem, fingerprint) do
    case Enum.reject([subsystem: subsystem, incident: fingerprint], fn {_k, v} -> is_nil(v) end) do
      [] -> ~p"/status"
      query -> ~p"/status?#{query}"
    end
  end

  # Resolves the durable incidents and optimistically evicts the buckets from the
  # local view (the Buckets cache also broadcasts the new list, which reconciles
  # any drift — but the optimistic update keeps the click instant).
  defp dismiss(socket, fingerprints) do
    ErrorReports.dismiss(fingerprints)
    remaining = Enum.reject(socket.assigns.error_buckets, &(&1.fingerprint in fingerprints))

    socket
    |> assign(error_buckets: remaining)
    |> assign_board()
  end

  defp drill_in_view(board, component), do: Enum.find(board, &(&1.component == component))

  defp drill_in_buckets(error_buckets, component) do
    HealthBoard.group_buckets(error_buckets)[component]
  end

  # Data bundle handed to whichever Activity widget is registered for the selected
  # subsystem. Superset of what any single widget reads; each widget declares (attr) its keys.
  defp activity_bundle(assigns) do
    %{
      # library overview
      overview: assigns.overview,
      # watcher
      dir_health: assigns.dir_health,
      watcher_statuses: assigns.watcher_statuses,
      scan_stats: assigns.scan_stats,
      storage_drives: assigns.storage_drives,
      at_risk_summary: assigns.at_risk_summary,
      ttl_days: Config.get(:file_absence_ttl_days) || 30,
      # pipeline
      content_stats: assigns.pipeline_stats,
      image_stats: assigns.image_pipeline_stats,
      retry_status: assigns.retry_status,
      pipeline_concurrency: assigns.pipeline_concurrency,
      image_concurrency: assigns.image_pipeline_concurrency,
      # tmdb
      config: assigns.config,
      metadata_stats: assigns.metadata_stats,
      low_confidence_count: assigns.overview && assigns.overview.pending_review_count,
      # http (connections)
      http_stats: assigns.http_stats,
      rate_limiter: assigns.rate_limiter,
      # playback
      playback: assigns.playback,
      playback_activity: assigns.playback_activity,
      # system runtime vitals
      system_vitals: assigns.system_vitals,
      # acquisition
      acquisition_activity: assigns.acquisition_activity,
      # friends
      relay_status: assigns.relay_status,
      friend_count: assigns.friend_count,
      sent_count: assigns.sent_count,
      received_count: assigns.received_count,
      last_received_at: assigns.last_received_at,
      # self_update — sourced from assigns + persistent_term (Config) + utc_now
      version: Version.current_version(),
      status: assigns.self_update_status,
      latest_release: assigns.self_update_release,
      last_check_at: assigns.self_update_last_check_at,
      history: assigns.self_update_history,
      now: DateTime.utc_now(),
      check_enabled?: Config.get(:update_check_enabled) == true,
      interval_minutes: Config.update_check_interval_minutes(),
      auto_install?: Config.get(:auto_update_enabled) == true,
      apply_phase: assigns.self_update_apply_phase,
      apply_progress: assigns.self_update_apply_progress
    }
  end

  # --- Events ---

  @impl true
  def handle_event("select_subsystem", %{"subsystem" => subsystem}, socket) do
    {:noreply, push_patch(socket, to: status_path(subsystem, nil))}
  end

  def handle_event("close_subsystem", _params, socket) do
    {:noreply, push_patch(socket, to: status_path(nil, nil))}
  end

  def handle_event("select_incident", %{"fingerprint" => fingerprint}, socket) do
    {:noreply, push_patch(socket, to: status_path(socket.assigns.selected_subsystem, fingerprint))}
  end

  def handle_event("close_incident", _params, socket) do
    {:noreply, push_patch(socket, to: status_path(socket.assigns.selected_subsystem, nil))}
  end

  # Hand off from the (ephemeral) issue view to the (persistent) report wizard:
  # open the wizard pre-loaded for this incident, then patch the incident out of
  # the URL so the issue view closes behind it (it can't co-exist with the wizard).
  def handle_event("report_incident_from_issue", %{"fingerprint" => _fp} = params, socket) do
    {:noreply, socket} = handle_event("open_error_report_modal", params, socket)
    {:noreply, push_patch(socket, to: status_path(socket.assigns.selected_subsystem, nil))}
  end

  def handle_event("dismiss_incident", %{"fingerprint" => fingerprint}, socket) do
    socket = dismiss(socket, [fingerprint])
    {:noreply, push_patch(socket, to: status_path(socket.assigns.selected_subsystem, nil))}
  end

  def handle_event("dismiss_all", _params, socket) do
    fingerprints =
      Enum.map(
        drill_in_buckets(socket.assigns.error_buckets, socket.assigns.selected_subsystem) || [],
        & &1.fingerprint
      )

    {:noreply, dismiss(socket, fingerprints)}
  end

  def handle_event("open_error_report_modal", params, socket) do
    buckets = socket.assigns.error_buckets

    bucket =
      case params["fingerprint"] do
        nil -> List.first(buckets)
        fp -> Enum.find(buckets, List.first(buckets), &(&1.fingerprint == fp))
      end

    payload =
      bucket &&
        MediaCentaur.ErrorReports.ReportPayload.build(
          bucket,
          MediaCentaur.ErrorReports.EnvMetadata.collect()
        )

    {:noreply,
     assign(socket,
       show_report_modal: not is_nil(payload),
       report_payload: payload,
       report_snapshot: nil
     )}
  end

  def handle_event("open_generic_report", _params, socket) do
    %{snapshot: snapshot, payload: payload} = MediaCentaur.ErrorReports.build_generic_report()

    {:noreply,
     assign(socket, show_report_modal: true, report_payload: payload, report_snapshot: snapshot)}
  end

  @impl true
  def handle_event("report_cancel", _params, socket) do
    {:noreply, assign(socket, show_report_modal: false, report_payload: nil, report_snapshot: nil)}
  end

  # --- Info handlers ---

  # The pipelines say when their picture changed (coalesced, silent when
  # idle); the page re-reads the snapshot then, never on a timer.
  @impl true
  def handle_info({:pipeline_stats_updated, :content}, socket) do
    {:noreply, assign(socket, pipeline_stats: Stats.get_snapshot(), rate_limiter: fetch_rate_limiter())}
  end

  def handle_info({:pipeline_stats_updated, :image}, socket) do
    {:noreply,
     assign(socket,
       image_pipeline_stats: ImagePipeline.Stats.get_snapshot(),
       retry_status: fetch_retry_status()
     )}
  end

  # HTTP figures ride the same tick: they are runtime measurements, not
  # a projection with a change event.
  def handle_info(:refresh_vitals, socket) do
    Process.send_after(self(), :refresh_vitals, @vitals_refresh_ms)

    {:noreply,
     assign(socket,
       system_vitals: Vitals.snapshot(),
       http_stats: MediaCentaur.HttpClient.Stats.snapshot(),
       rate_limiter: fetch_rate_limiter()
     )}
  end

  # Status.Views projection refreshed (library overview: entity/review
  # events + interval; storage: availability/watcher/config events +
  # interval). Re-read is an ETS lookup — no debounce needed; the
  # projection's Cache.Worker already serializes refreshes.
  def handle_info({:status_view_updated, :overview}, socket) do
    {:noreply, assign(socket, overview: Status.Views.overview())}
  end

  def handle_info({:status_view_updated, :storage}, socket) do
    {:noreply, assign_storage_snapshot(socket, Status.Views.storage())}
  end

  def handle_info({:dir_state_changed, _dir, _role, _state}, socket) do
    # The at-risk/storage side of a dir flip arrives separately via the
    # Storage projection (it subscribes to the same watcher topic).
    {:noreply,
     socket
     |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
     |> assign(image_dir_statuses: MediaCentaur.Watcher.Supervisor.image_dir_statuses())
     |> assign(scan_stats: MediaCentaur.Watcher.Supervisor.scan_stats())}
  end

  @impl true
  def handle_info({:buckets_changed, snapshot}, socket) do
    {:noreply, socket |> assign(error_buckets: snapshot) |> assign_board()}
  end

  def handle_info(
        {:playback_state_changed,
         %{entity_id: entity_id, state: new_state, now_playing: now_playing, started_at: started_at}},
        socket
      ) do
    sessions = socket.assigns.playback.sessions
    existing = Map.get(sessions, entity_id)
    kept_started_at = (existing && existing[:started_at]) || started_at

    sessions =
      apply_playback_change(sessions, entity_id, new_state, now_playing, %{
        started_at: kept_started_at
      })

    {:noreply, assign(socket, playback: derive_playback(sessions))}
  end

  def handle_info(
        {:entity_progress_updated, %{entity_id: entity_id, changed_record: changed_record}},
        socket
      ) do
    sessions = socket.assigns.playback.sessions

    socket =
      with %{now_playing: now_playing} = session when not is_nil(now_playing) <-
             Map.get(sessions, entity_id),
           %{} = record <- changed_record,
           true <- progress_matches_session?(record, now_playing) do
        updated =
          Map.merge(now_playing, %{
            position_seconds: record.position_seconds,
            duration_seconds: record.duration_seconds
          })

        updated_sessions =
          Map.put(sessions, entity_id, %{session | now_playing: updated})

        assign(socket, playback: derive_playback(updated_sessions))
      else
        _ -> socket
      end

    {:noreply, socket}
  end

  # --- Self-update subsystem (Updates widget) ---

  def handle_info({:check_started}, socket) do
    {:noreply, assign(socket, self_update_status: :checking)}
  end

  def handle_info({:check_complete, {classification, release}, _source}, socket)
      when classification in [:update_available, :up_to_date, :ahead_of_release] do
    {:noreply,
     assign(socket,
       self_update_status: classification,
       self_update_release: release,
       self_update_last_check_at: SelfUpdate.last_check_at()
     )}
  end

  def handle_info({:check_complete, {:error, reason}, _source}, socket) do
    {:noreply, assign(socket, self_update_status: {:error, reason})}
  end

  def handle_info({:progress, phase, pct}, socket) do
    {:noreply, assign(socket, self_update_apply_phase: phase, self_update_apply_progress: pct)}
  end

  def handle_info({:apply_failed, _reason}, socket) do
    {:noreply, assign(socket, self_update_apply_phase: :failed)}
  end

  def handle_info({:apply_cancelled}, socket) do
    {:noreply, assign(socket, self_update_apply_phase: nil, self_update_apply_progress: nil)}
  end

  @impl true
  def handle_info({msg, _payload}, socket)
      when msg in [:watch_event_created, :watch_completed, :watch_event_deleted] do
    {:noreply,
     assign(socket,
       playback_activity: PlaybackActivity.snapshot()
     )}
  end

  @impl true
  def handle_info({:queue_state, _state}, socket) do
    {:noreply, assign(socket, acquisition_activity: build_acquisition_activity())}
  end

  def handle_info(:capabilities_changed, socket) do
    {:noreply, assign(socket, acquisition_activity: build_acquisition_activity())}
  end

  # `Connections.apply_message/2` is the owner's own fold, so this page and
  # the owner can never disagree about what a connection message means.
  # Only relays this page has loaded are folded — the configured set comes
  # from the relay rows, and a message about one it does not know belongs
  # to a row added or removed since; the next navigation picks that up.
  def handle_info({:relay_connection, url, message}, socket) do
    case Map.fetch(socket.assigns.relay_status, url) do
      {:ok, entry} ->
        status = Map.put(socket.assigns.relay_status, url, Connections.apply_message(entry, message))
        {:noreply, assign(socket, relay_status: status)}

      :error ->
        {:noreply, socket}
    end
  end

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      show_discovery={@show_discovery}
      show_apps={@show_apps}
      flash={@flash}
      current_path="/status"
      badges={assigns[:badges] || %MediaCentaurWeb.ShellBadges.Counts{}}
    >
      <:overlays>
        <%!-- Persistent, form-heavy wizard — deliberately NOT a
              data-detail-mode context (BACK must not dismiss it).
              data-captures-keys keeps every key inside it (textarea,
              wizard buttons) away from the nav system; see the
              unmanaged-overlay note in core/dom_adapter.js. --%>
        <.modal
          :if={@show_report_modal}
          id="error-report-modal"
          open
          dismiss={:persistent}
          data-testid="report-modal"
          data-captures-keys
          panel_class="flex flex-col max-h-[calc(88*var(--pvh))]"
        >
          <.live_component
            id="report-modal-body"
            module={ReportModal}
            payload={@report_payload}
            snapshot={@report_snapshot}
          />
        </.modal>
        <%!-- Always mounted (toggles via data-state) like our best modals, so the
              blur layer stays warm; inner content is guarded on the bucket. --%>
        <IssueView.issue_view bucket={@selected_incident} />
      </:overlays>
      <div class="relative" data-page-behavior="status" data-nav-default-zone="status">
        <%!-- Scrim only, same as Settings: no content entity to source a hero
              from, so the calm dim ramp supplies the darker sense-of-place
              without a backdrop. Fixed + behind content (z-0). --%>
        <div class="page-side-dim page-side-dim-calm" aria-hidden="true"></div>

        <div class="relative z-[1] space-y-6">
          <div data-nav-zone="toolbar" class="flex items-center gap-3">
            <.page_header title="Status" />
            <div class="flex-1"></div>
            <.button
              variant="outline"
              size="sm"
              data-testid="report-a-problem"
              phx-click="open_generic_report"
              data-nav-item
              tabindex="0"
            >
              Report a problem
            </.button>
          </div>

          <div class="space-y-7">
            <%!-- The tile board is the page's GRID context (spatial nav reads
                the container's computed columns), so the zone name is the
                framework's literal `grid`. --%>
            <div
              data-nav-zone="grid"
              class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3"
            >
              <.subsystem_tile
                :for={view <- @board}
                view={view}
                selected={view.component == @selected_subsystem}
              />
            </div>

            <.health_drill_in
              :if={@selected_subsystem}
              view={drill_in_view(@board, @selected_subsystem)}
              buckets={drill_in_buckets(@error_buckets, @selected_subsystem)}
              retention={Map.get(@retention_by_subsystem, @selected_subsystem, [])}
              on_select="select_incident"
            >
              <:activity :if={ActivityWidgets.widget_for(@selected_subsystem)}>
                {ActivityWidgets.render(@selected_subsystem, activity_bundle(assigns))}
              </:activity>
            </.health_drill_in>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Acquisition Activity ---

  defp build_acquisition_activity do
    state = QueueMonitor.state()

    %{
      configured?: Capabilities.download_client_ready?() or Capabilities.prowlarr_ready?(),
      connectivity: state.connectivity,
      last_poll_at: state.last_successful_poll_at,
      prowlarr_ready?: Capabilities.prowlarr_ready?(),
      throughput: Throughput.stats()
    }
  end

  # --- Playback State ---

  defp build_playback_state do
    sessions =
      Map.new(MediaCentaur.Playback.Sessions.list(), fn session ->
        {session.entity_id,
         %{
           state: session.state,
           now_playing: session.now_playing,
           started_at: session.started_at
         }}
      end)

    derive_playback(sessions)
  end

  # Derives the status page's single-card playback view from the sessions map.
  # Shows the most recently active session (playing > paused).

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp fetch_retry_status do
    %{retrying_count: MediaCentaur.Pipeline.ImageQueue.retrying_count()}
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp load_config do
    config = MediaCentaur.Settings.Config

    %{
      tmdb_configured: MediaCentaur.Secret.present?(config.get(:tmdb_api_key)),
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      media_dirs_count: length(config.get(:media_dirs) || [])
    }
  end
end
