defmodule MediaCentaurWeb.StatusLive do
  @moduledoc """
  Operational status page at `/status`.

  Surfaces the Subsystem Health Board, pending review count, pipeline health,
  watcher state, storage metrics, external integrations, and active playback
  summary. The library itself lives at `/`; this page is the
  developer/operator view.
  """
  use MediaCentaurWeb, :live_view

  require MediaCentaur.Log, as: Log

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.HealthComponents

  alias MediaCentaur.{Config, ErrorReports, Playback, SelfUpdate, Status, Storage}
  alias MediaCentaur.Version
  alias MediaCentaurWeb.StatusLive.ActivityWidgets
  alias MediaCentaurWeb.StatusLive.HealthBoard
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.Pipeline.Image, as: ImagePipeline
  alias MediaCentaur.Watcher
  alias MediaCentaur.Library.AbsenceSweeper
  alias MediaCentaurWeb.StatusLive.ReportModal

  @storage_refresh_ms 5 * 60 * 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Watcher.Supervisor.subscribe()
        Playback.subscribe()
        ErrorReports.subscribe()
        SelfUpdate.subscribe()
        SelfUpdate.subscribe_progress()
        MediaCentaur.Library.subscribe()

        # Visiting /status marks auto-detected incidents as seen, clearing
        # the discovery badge on the Status nav item. The web layer owns
        # the diagnostics_seen_at timestamp (DiagnosticsBadge), so the
        # ErrorReports context stays free of any Settings dependency.
        MediaCentaurWeb.DiagnosticsBadge.mark_seen()

        Process.send_after(self(), :tick_pipeline, 1_000)
        Process.send_after(self(), :refresh_storage, @storage_refresh_ms)

        pipeline_stats = Stats.get_snapshot()
        image_stats = ImagePipeline.Stats.get_snapshot()

        # Kick off expensive queries off the mount path via owned async.
        # Mount returns immediately with empty defaults; each task fills
        # its slice in via handle_async. Keeps /status responsive even
        # with a big library and watch dirs on slow / sleeping storage.
        socket
        |> assign_defaults()
        |> assign(error_buckets: ErrorReports.list_buckets())
        |> assign_board()
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(image_pipeline_stats: image_stats)
        |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
        |> assign(image_dir_statuses: MediaCentaur.Watcher.Supervisor.image_dir_statuses())
        |> assign(config: load_config())
        |> assign(rate_limiter: fetch_rate_limiter())
        |> assign(retry_status: fetch_retry_status())
        |> assign(playback: build_playback_state())
        |> assign(diagnostics_unseen: 0)
        |> assign_self_update()
        |> start_async_storage()
        |> start_async_dir_health()
        |> start_async_overview()
      else
        socket
        |> assign_defaults()
        |> assign(pipeline_stats: Stats.empty_snapshot())
        |> assign(image_pipeline_stats: ImagePipeline.Stats.empty_snapshot())
        |> assign(watcher_statuses: [])
        |> assign(image_dir_statuses: [])
        |> assign(dir_health: [])
        |> assign(config: %{})
        |> assign(rate_limiter: nil)
        |> assign(retry_status: nil)
        |> assign(playback: %{state: :idle, now_playing: nil, sessions: %{}})
      end

    {:ok,
     assign(socket,
       pipeline_concurrency: MediaCentaur.Pipeline.Discovery.processor_concurrency(),
       image_pipeline_concurrency: 8
     )}
  end

  defp assign_defaults(socket) do
    socket
    |> assign(error_buckets: [])
    |> assign(board: HealthBoard.build_board([]))
    |> assign(selected_subsystem: nil)
    |> assign(overview: nil)
    |> assign(overview_refresh_pending: false)
    |> assign(storage_drives: [])
    |> assign(at_risk_summary: %{})
    |> assign(dir_health: [])
    |> assign(show_report_modal: false)
    |> assign(report_payload: nil)
    |> assign(report_snapshot: nil)
    |> assign(self_update_status: :idle)
    |> assign(self_update_release: nil)
    |> assign(self_update_last_check_at: :none)
    |> assign(self_update_apply_phase: nil)
    |> assign(self_update_apply_progress: nil)
  end

  # Snapshot of the self-update subsystem for the Updates Activity widget.
  # `last_check_at` (a Settings read) is captured into assigns and refreshed on
  # `{:check_complete, …}` — because it changes rarely, not because the render
  # path must avoid DB reads.
  #
  # Tombstone: this used to defer the read "to keep `activity_bundle/1` free of
  # DB queries on the render path (ADR-012)." That rule is retired — ADR-051
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
      self_update_apply_phase: if(phase != :idle, do: phase)
    )
  end

  # Keeps the board view-models in sync with the current `error_buckets`.
  defp assign_board(socket) do
    assign(socket, board: HealthBoard.build_board(socket.assigns.error_buckets))
  end

  # Owned async (ADR-049): each load runs under the LiveView via
  # `start_async/3` — cancelled with it, awaitable in tests, never an
  # orphan under the global supervisor. Results land in the matching
  # `handle_async/3` clauses below.
  defp start_async_storage(socket) do
    start_async(socket, :status_storage, fn ->
      %{drives: Storage.measure_all(), at_risk: AbsenceSweeper.at_risk_summary()}
    end)
  end

  defp start_async_dir_health(socket) do
    start_async(socket, :status_dir_health, fn -> check_dir_health() end)
  end

  # The overview runs a per-image disk check (Maintenance.missing_images_summary/0)
  # and several library counts, so it never belongs on the mount path — it lands
  # via `handle_async(:status_overview, …)`.
  defp start_async_overview(socket) do
    start_async(socket, :status_overview, fn -> Status.fetch_overview() end)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, selected_subsystem: parse_subsystem(params))}
  end

  defp parse_subsystem(%{"subsystem" => raw}) do
    atom = safe_existing_atom(raw)
    if atom in HealthBoard.board_subsystems(), do: atom
  end

  defp parse_subsystem(_params), do: nil

  defp safe_existing_atom(raw) do
    String.to_existing_atom(raw)
  rescue
    ArgumentError -> nil
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
      rate_limiter: assigns.rate_limiter,
      config: assigns.config,
      # playback
      playback: assigns.playback,
      # self_update — sourced from assigns + persistent_term (Config) + utc_now
      version: Version.current_version(),
      status: assigns.self_update_status,
      latest_release: assigns.self_update_release,
      last_check_at: assigns.self_update_last_check_at,
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
    {:noreply, push_patch(socket, to: ~p"/status?subsystem=#{subsystem}")}
  end

  def handle_event("close_subsystem", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/status")}
  end

  def handle_event("dismiss_incident", %{"fingerprint" => fingerprint}, socket) do
    {:noreply, dismiss(socket, [fingerprint])}
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

  @impl true
  def handle_info(:tick_pipeline, socket) do
    Process.send_after(self(), :tick_pipeline, 1_000)
    pipeline_stats = Stats.get_snapshot()
    image_stats = ImagePipeline.Stats.get_snapshot()

    {:noreply,
     socket
     |> assign(pipeline_stats: pipeline_stats)
     |> assign(image_pipeline_stats: image_stats)
     |> assign(rate_limiter: fetch_rate_limiter())
     |> assign(retry_status: fetch_retry_status())
     |> start_async_dir_health()}
  end

  def handle_info(:refresh_storage, socket) do
    Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
    {:noreply, socket |> start_async_storage() |> start_async_overview()}
  end

  # Library changed (import, edit, delete). Debounce: a bulk import fires this
  # many times, but a single recompute 2s after the last change suffices. The
  # pending flag collapses the storm into one refresh.
  def handle_info({:entities_changed, _payload}, socket) do
    if socket.assigns.overview_refresh_pending do
      {:noreply, socket}
    else
      Process.send_after(self(), :refresh_overview, 2_000)
      {:noreply, assign(socket, overview_refresh_pending: true)}
    end
  end

  def handle_info(:refresh_overview, socket) do
    {:noreply, socket |> assign(overview_refresh_pending: false) |> start_async_overview()}
  end

  def handle_info({:dir_state_changed, _dir, _role, _state}, socket) do
    # Reload the at-risk summary too: a flip to :unavailable stops
    # presence refreshes (count of stale rows ticks up over time), and
    # a flip to :available resets last_seen_at for the dir
    # (earliest_absent_since advances) via Library.AbsenceSweeper. The
    # badge that drives the user's "drive offline N days, X files at
    # risk" warning needs both reflected promptly.
    {:noreply,
     socket
     |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
     |> assign(image_dir_statuses: MediaCentaur.Watcher.Supervisor.image_dir_statuses())
     |> start_async_storage()}
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

  def handle_info({:check_complete, {classification, release}}, socket)
      when classification in [:update_available, :up_to_date, :ahead_of_release] do
    {:noreply,
     assign(socket,
       self_update_status: classification,
       self_update_release: release,
       self_update_last_check_at: SelfUpdate.last_check_at()
     )}
  end

  def handle_info({:check_complete, {:error, reason}}, socket) do
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

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Async results (owned via start_async/3, ADR-049) ---

  @impl true
  def handle_async(:status_storage, {:ok, %{drives: drives, at_risk: at_risk}}, socket) do
    {:noreply,
     socket
     |> assign(storage_drives: drives)
     |> assign(at_risk_summary: at_risk)}
  end

  def handle_async(:status_dir_health, {:ok, dir_health}, socket) do
    {:noreply, assign(socket, dir_health: dir_health)}
  end

  def handle_async(:status_overview, {:ok, overview}, socket) do
    {:noreply, assign(socket, overview: overview)}
  end

  def handle_async(name, {:exit, reason}, socket) do
    Log.warning(:status, "status async #{inspect(name)} failed — #{inspect(reason)}")
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app
      flash={@flash}
      current_path="/status"
      acquisition_ready={@acquisition_ready}
      diagnostics_unseen={assigns[:diagnostics_unseen] || 0}
    >
      <:overlays>
        <.live_component
          :if={@show_report_modal}
          id="error-report-modal"
          module={ReportModal}
          payload={@report_payload}
          snapshot={@report_snapshot}
        />
      </:overlays>
      <div data-page-behavior="status" data-nav-default-zone="status" class="space-y-6">
        <div class="flex items-center gap-3">
          <h1 class="text-2xl font-bold">Status</h1>
          <div class="flex-1"></div>
          <.button
            variant="outline"
            size="sm"
            data-testid="report-a-problem"
            phx-click="open_generic_report"
          >
            Report a problem
          </.button>
        </div>

        <div class="space-y-7">
          <div
            data-nav-zone="health-board"
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
            on_report="open_error_report_modal"
          >
            <:activity :if={ActivityWidgets.widget_for(@selected_subsystem)}>
              {ActivityWidgets.render(@selected_subsystem, activity_bundle(assigns))}
            </:activity>
          </.health_drill_in>
        </div>
      </div>
    </Layouts.app>
    """
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
    config = MediaCentaur.Config

    %{
      tmdb_configured: MediaCentaur.Secret.present?(config.get(:tmdb_api_key)),
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

  defp check_dir_health do
    watch_dirs = MediaCentaur.Config.get(:watch_dirs) || []

    Enum.map(watch_dirs, fn dir ->
      image_dir = MediaCentaur.Config.images_dir_for(dir)

      %{
        dir: dir,
        dir_exists: File.dir?(dir),
        image_dir: image_dir,
        image_dir_exists: File.dir?(image_dir)
      }
    end)
  end
end
