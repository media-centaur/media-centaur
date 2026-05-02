defmodule MediaCentarrWeb.StatusLive do
  @moduledoc """
  Operational status page at `/status`.

  Surfaces library counts, pipeline health, watcher state, storage metrics,
  external integrations, recent errors, the recent-changes feed, and the
  active playback summary. The library itself lives at `/`; this page is the
  developer/operator view.
  """
  use MediaCentarrWeb, :live_view

  import MediaCentarrWeb.StatusHelpers

  alias MediaCentarr.{ErrorReports, Library, Playback, Status, Storage, WatchHistory}
  alias MediaCentarr.Pipeline.Stats
  alias MediaCentarr.Pipeline.Image, as: ImagePipeline
  alias MediaCentarr.Watcher
  alias MediaCentarrWeb.StatusLive.ReportModal

  @storage_refresh_ms 5 * 60 * 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Watcher.Supervisor.subscribe()
        Library.subscribe()
        Playback.subscribe()
        WatchHistory.subscribe()
        ErrorReports.subscribe()

        Process.send_after(self(), :tick_pipeline, 1_000)
        Process.send_after(self(), :refresh_storage, @storage_refresh_ms)

        pipeline_stats = Stats.get_snapshot()
        image_stats = ImagePipeline.Stats.get_snapshot()

        # Kick off expensive queries off the mount path. Mount returns
        # immediately with empty defaults; each task sends a message back
        # when ready. Keeps /status responsive even with a big library.
        start_async_status_stats()
        start_async_watch_history()
        start_async_storage()

        socket
        |> assign_defaults()
        |> assign(error_buckets: ErrorReports.list_buckets())
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(image_pipeline_stats: image_stats)
        |> assign(watcher_statuses: MediaCentarr.Watcher.Supervisor.statuses())
        |> assign(image_dir_statuses: MediaCentarr.Watcher.Supervisor.image_dir_statuses())
        |> assign(dir_health: check_dir_health())
        |> assign(config: load_config())
        |> assign(rate_limiter: fetch_rate_limiter())
        |> assign(retry_status: fetch_retry_status())
        |> assign(playback: build_playback_state())
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
       stats_timer: nil,
       pipeline_concurrency: MediaCentarr.Pipeline.Discovery.processor_concurrency(),
       image_pipeline_concurrency: 8
     )}
  end

  defp assign_defaults(socket) do
    socket
    |> assign(library_stats: %{episodes: 0, files: 0, images: 0, by_type: %{}})
    |> assign(pending_review_count: 0)
    |> assign(recent_changes: [])
    |> assign(history_events: [])
    |> assign(history_stats: %{total_count: 0, total_seconds: 0.0, streak: 0, heatmap: %{}})
    |> assign(error_buckets: [])
    |> assign(storage_drives: [])
    |> assign(show_report_modal: false)
  end

  defp start_async_status_stats do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      send(parent, {:status_stats_loaded, Status.fetch_stats()})
    end)
  end

  defp start_async_watch_history do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      send(parent, {:status_history_loaded, WatchHistory.stats(), WatchHistory.recent_events(5)})
    end)
  end

  defp start_async_storage do
    parent = self()

    Task.Supervisor.start_child(MediaCentarr.TaskSupervisor, fn ->
      send(parent, {:status_storage_loaded, Storage.measure_all()})
    end)
  end

  # --- Events ---

  @impl true
  def handle_event("open_error_report_modal", _params, socket) do
    {:noreply, assign(socket, show_report_modal: true)}
  end

  @impl true
  def handle_event("report_cancel", _params, socket) do
    {:noreply, assign(socket, show_report_modal: false)}
  end

  @impl true
  def handle_event("report_confirm", %{"fingerprint" => fingerprint}, socket) do
    bucket = Enum.find(socket.assigns.error_buckets, &(&1.fingerprint == fingerprint))

    socket =
      case bucket do
        nil ->
          socket

        bucket ->
          env = MediaCentarr.ErrorReports.EnvMetadata.collect()
          {:ok, url, _flags} = MediaCentarr.ErrorReports.IssueUrl.build(bucket, env)
          push_event(socket, "error_reports:open_issue", %{url: url})
      end

    {:noreply, assign(socket, show_report_modal: false)}
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
     |> assign(dir_health: check_dir_health())}
  end

  def handle_info(:refresh_storage, socket) do
    Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
    start_async_storage()
    {:noreply, socket}
  end

  def handle_info({:dir_state_changed, _dir, _role, _state}, socket) do
    {:noreply,
     socket
     |> assign(watcher_statuses: MediaCentarr.Watcher.Supervisor.statuses())
     |> assign(image_dir_statuses: MediaCentarr.Watcher.Supervisor.image_dir_statuses())}
  end

  def handle_info({:entities_changed, %{entity_ids: _entity_ids}}, socket) do
    {:noreply, debounce(socket, :stats_timer, :refresh_stats, 1_000)}
  end

  def handle_info(:refresh_stats, socket) do
    start_async_status_stats()
    start_async_watch_history()
    {:noreply, assign(socket, stats_timer: nil)}
  end

  @impl true
  def handle_info({:buckets_changed, snapshot}, socket) do
    {:noreply, assign(socket, error_buckets: snapshot)}
  end

  def handle_info({:status_stats_loaded, stats}, socket) do
    {:noreply,
     socket
     |> assign(library_stats: stats.library)
     |> assign(pending_review_count: length(stats.pending_review))
     |> assign(recent_changes: stats.recent_changes)}
  end

  def handle_info({:status_history_loaded, history_stats, history_events}, socket) do
    {:noreply,
     socket
     |> assign(:history_events, history_events)
     |> assign(:history_stats, history_stats)}
  end

  def handle_info({:status_storage_loaded, drives}, socket) do
    {:noreply, assign(socket, storage_drives: drives)}
  end

  def handle_info({:watch_event_created, _event}, socket) do
    {:noreply, debounce(socket, :stats_timer, :refresh_stats, 1_000)}
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

  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.console_mount socket={@socket} />
    <Layouts.app flash={@flash} current_path="/status">
      <div data-page-behavior="status" data-nav-default-zone="status" class="space-y-6">
        <h1 class="text-2xl font-bold">Status</h1>

        <div data-nav-zone="sections">
          <.library_stats stats={@library_stats} pending_review_count={@pending_review_count} />

          <div class="grid grid-cols-1 lg:grid-cols-2 gap-6 mt-6">
            <.recent_changes_card entries={@recent_changes} />
            <.recently_watched_card events={@history_events} />
          </div>

          <.error_summary_card buckets={@error_buckets} />

          <.link navigate="/settings?section=services" data-nav-item tabindex="0" class="block mt-6">
            <div class="grid grid-cols-1 lg:grid-cols-[3fr_2fr] gap-6">
              <.pipeline_card
                content_stats={@pipeline_stats}
                image_stats={@image_pipeline_stats}
                retry_status={@retry_status}
                pipeline_concurrency={@pipeline_concurrency}
                image_concurrency={@image_pipeline_concurrency}
              />

              <div class="flex flex-col gap-6">
                <.playback_summary_card playback={@playback} />
                <.external_integrations rate_limiter={@rate_limiter} config={@config} />
              </div>
            </div>
          </.link>

          <.link
            navigate="/settings?section=configuration"
            data-nav-item
            tabindex="0"
            class="block mt-6"
          >
            <.directories
              dir_health={@dir_health}
              watcher_statuses={@watcher_statuses}
              storage_drives={@storage_drives}
            />
          </.link>
        </div>
      </div>

      <.live_component
        :if={@show_report_modal}
        id="report-modal-component"
        module={ReportModal}
        buckets={@error_buckets}
      />
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp library_stats(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
      <.link navigate="/library" data-nav-item tabindex="0" class="p-4 rounded-lg glass-surface block">
        <div class="text-2xl font-bold">{@stats.by_type[:movie] || 0}</div>
        <div class="text-sm text-base-content/60">Movies</div>
        <div class="text-xs text-base-content/40 mt-1">
          {@stats.by_type[:movie_series] || 0} collections
        </div>
      </.link>
      <.link navigate="/library" data-nav-item tabindex="0" class="p-4 rounded-lg glass-surface block">
        <div class="text-2xl font-bold">{@stats.by_type[:tv_series] || 0}</div>
        <div class="text-sm text-base-content/60">TV Series</div>
        <div class="text-xs text-base-content/40 mt-1">{@stats.episodes} episodes</div>
      </.link>
      <.link
        :if={(@stats.by_type[:video_object] || 0) > 0}
        navigate="/library"
        data-nav-item
        tabindex="0"
        class="p-4 rounded-lg glass-surface block"
      >
        <div class="text-2xl font-bold">{@stats.by_type[:video_object]}</div>
        <div class="text-sm text-base-content/60">Videos</div>
      </.link>
      <.link navigate="/library" data-nav-item tabindex="0" class="p-4 rounded-lg glass-surface block">
        <div class="text-2xl font-bold">{@stats.files}</div>
        <div class="text-sm text-base-content/60">Files Tracked</div>
      </.link>
      <.link navigate="/library" data-nav-item tabindex="0" class="p-4 rounded-lg glass-surface block">
        <div class="text-2xl font-bold">{@stats.images}</div>
        <div class="text-sm text-base-content/60">Images Cached</div>
      </.link>
      <.link
        navigate={~p"/review"}
        data-nav-item
        tabindex="0"
        class={[
          "p-4 rounded-lg glass-surface block",
          if(@pending_review_count > 0, do: "border-l-3 border-warning")
        ]}
      >
        <div class="text-2xl font-bold">{@pending_review_count}</div>
        <div class="text-sm text-base-content/60">Pending Review</div>
      </.link>
    </div>
    """
  end

  defp recent_changes_card(assigns) do
    ~H"""
    <div data-nav-item data-status-releases tabindex="0" class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Recent Changes</h2>

        <p :if={@entries == []} class="text-base-content/60">No changes yet.</p>

        <ul :if={@entries != []} class="space-y-1">
          <li :for={entry <- @entries}>
            <.change_entry_row entry={entry} />
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp change_entry_row(%{entry: %{kind: :added}} = assigns) do
    ~H"""
    <.link
      navigate={"/library?selected=#{@entry.entity_id}"}
      class="flex items-center gap-3 py-1 hover:bg-base-content/5 rounded px-2 -mx-2"
    >
      <span class="w-2 h-2 rounded-full bg-success shrink-0"></span>
      <span class="text-sm truncate flex-1">{@entry.entity_name}</span>
      <span class="text-xs text-base-content/50">
        {MediaCentarrWeb.LibraryFormatters.format_type(@entry.entity_type)}
      </span>
      <span class="text-xs text-base-content/40 whitespace-nowrap">
        {MediaCentarrWeb.LiveHelpers.time_ago(@entry.inserted_at)}
      </span>
    </.link>
    """
  end

  defp change_entry_row(%{entry: %{kind: :removed}} = assigns) do
    ~H"""
    <div class="flex items-center gap-3 py-1 px-2 -mx-2">
      <span class="w-2 h-2 rounded-full bg-error shrink-0"></span>
      <span class="text-sm truncate flex-1 text-base-content/60">{@entry.entity_name}</span>
      <span class="text-xs text-base-content/50">
        {MediaCentarrWeb.LibraryFormatters.format_type(@entry.entity_type)}
      </span>
      <span class="text-xs text-base-content/40 whitespace-nowrap">
        {MediaCentarrWeb.LiveHelpers.time_ago(@entry.inserted_at)}
      </span>
    </div>
    """
  end

  defp recently_watched_card(assigns) do
    ~H"""
    <.link navigate={~p"/history"} data-nav-item tabindex="0" class="card glass-surface block">
      <div class="card-body">
        <div class="flex items-center justify-between mb-1">
          <h2 class="card-title text-lg">Recently Watched</h2>
          <span class="text-xs text-primary/70">view all</span>
        </div>

        <p :if={@events == []} class="text-base-content/60">Nothing watched yet.</p>

        <ul :if={@events != []} class="space-y-1">
          <li
            :for={event <- @events}
            class="flex items-center justify-between gap-4 py-1"
          >
            <span class="text-sm truncate">{event.title}</span>
            <span class="text-xs text-base-content/40 whitespace-nowrap flex-shrink-0">
              {time_ago(event.completed_at)}
            </span>
          </li>
        </ul>
      </div>
    </.link>
    """
  end

  @stage_grid_columns "grid-template-columns: 0.5rem 1fr 5rem 4.5rem 4.5rem 3rem"

  defp pipeline_card(assigns) do
    assigns =
      assigns
      |> assign(:stage_order, [:parse, :search, :fetch_metadata, :ingest])
      |> assign(:grid_columns, @stage_grid_columns)

    ~H"""
    <div class="card glass-surface self-start">
      <div class="card-body">
        <%!-- Pipeline header --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Pipeline</h2>
          <div class="flex items-center gap-3 text-sm">
            <span :if={@content_stats.queue_depth > 0} class="text-info text-sm">
              {@content_stats.queue_depth} queued
            </span>
            <span :if={@content_stats.total_failed > 0} class="text-error text-xs">
              {@content_stats.total_failed} failed
            </span>
          </div>
        </div>

        <%!-- New Media section with column headers --%>
        <div
          class="grid items-center gap-2 mt-3 mb-1"
          style={@grid_columns}
        >
          <span></span>
          <span class="text-xs text-base-content/50 uppercase tracking-wide">New Media</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide">Status</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Rate</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Avg</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Slots</span>
        </div>

        <%!-- Content pipeline stages --%>
        <div class="space-y-0.5">
          <.pipeline_stage
            :for={stage <- @stage_order}
            stage={stage}
            data={@content_stats.stages[stage]}
            concurrency={@pipeline_concurrency}
            grid_columns={@grid_columns}
          />
        </div>

        <%!-- Images section --%>
        <h3 class="text-xs text-base-content/50 uppercase tracking-wide mt-3">Images</h3>

        <%!-- Image pipeline row — same grid as content stages --%>
        <div
          class="grid items-center gap-2 py-1"
          style={@grid_columns}
        >
          <span class={["w-2 h-2 rounded-full", stage_dot_class(@image_stats.status)]}></span>

          <span class="text-sm font-medium truncate">
            Download + Resize
            <span :if={@image_stats.last_error} class="text-error text-xs font-normal ml-2">
              {elem(@image_stats.last_error, 0)}
            </span>
          </span>

          <span class={["text-xs", stage_text_class(@image_stats.status)]}>
            {stage_status_label(@image_stats.status)}
          </span>

          <span class="text-xs font-mono text-base-content/60 text-right">
            {format_throughput(@image_stats.throughput)}
          </span>

          <span class="text-xs font-mono text-base-content/60 text-right">
            {format_duration(@image_stats.avg_duration_ms)}
          </span>

          <span class="text-xs font-mono text-base-content/40 text-right">
            {@image_stats.active_count}/{@image_concurrency}
          </span>
        </div>

        <div
          :if={
            @image_stats.total_downloaded > 0 or @image_stats.total_failed > 0 or
              @image_stats.queue_depth > 0 or
              (@retry_status && @retry_status.retrying_count > 0)
          }
          class="flex items-center gap-3 text-xs text-base-content/50 ml-6"
        >
          <span :if={@image_stats.total_downloaded > 0}>
            {@image_stats.total_downloaded} downloaded
          </span>
          <span :if={@image_stats.total_failed > 0} class="text-error">
            {@image_stats.total_failed} failed
          </span>
          <span :if={@image_stats.queue_depth > 0}>
            {@image_stats.queue_depth} queued
          </span>
          <span :if={@retry_status && @retry_status.retrying_count > 0} class="text-warning">
            {@retry_status.retrying_count} retrying
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp pipeline_stage(assigns) do
    ~H"""
    <div
      class="grid items-center gap-2 py-1"
      style={@grid_columns}
    >
      <span class={["w-2 h-2 rounded-full", stage_dot_class(@data.status)]}></span>

      <span class="text-sm font-medium truncate">
        {stage_display_name(@stage)}
        <span :if={@data.last_error} class="text-error text-xs font-normal ml-2">
          {elem(@data.last_error, 0)}
        </span>
      </span>

      <span class={["text-xs", stage_text_class(@data.status)]}>
        {stage_status_label(@data.status)}
      </span>

      <span class="text-xs font-mono text-base-content/60 text-right">
        {format_throughput(@data.throughput)}
      </span>

      <span class="text-xs font-mono text-base-content/60 text-right">
        {format_duration(@data.avg_duration_ms)}
      </span>

      <span class="text-xs font-mono text-base-content/40 text-right">
        {@data.active_count}/{@concurrency}
      </span>
    </div>
    """
  end

  defp directories(assigns) do
    db_drive =
      Enum.find(assigns.storage_drives, fn drive ->
        Enum.any?(drive.roles, &(&1.label == "Database"))
      end)

    assigns = assign(assigns, :db_drive, db_drive)

    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Directories</h2>

        <p :if={@dir_health == []} class="text-base-content/60">
          No watch directories configured.
        </p>

        <div :if={@dir_health != []} class="space-y-4">
          <div :for={health <- @dir_health}>
            <% status = resolve_dir_status(health, @watcher_statuses) %>
            <% drive = find_drive_for_dir(@storage_drives, health.dir) %>

            <div class="flex items-center gap-3 mb-1">
              <span
                :if={health.image_dir_exists}
                class="text-xs text-success whitespace-nowrap shrink-0"
              >
                images: ok
              </span>
              <span
                :if={!health.image_dir_exists}
                class="text-xs text-error whitespace-nowrap shrink-0"
              >
                images: missing
              </span>
              <code
                class="text-sm truncate-left flex-1"
                title={health.dir}
              >
                <bdo dir="ltr">{health.dir}</bdo>
              </code>
              <span
                :if={health.dir_exists && drive}
                class="text-xs font-mono text-base-content/60 shrink-0"
              >
                {format_bytes(drive.used_bytes)} / {format_bytes(drive.total_bytes)}
              </span>
              <span :if={!health.dir_exists} class="text-xs text-base-content/40 shrink-0">
                —
              </span>
              <span class={["text-xs shrink-0", dir_status_text_class(status)]}>
                {dir_status_label(status)}
              </span>
            </div>

            <div :if={health.dir_exists && drive} class="flex items-center gap-3 mt-1">
              <progress
                class={["progress h-1.5 flex-1", usage_progress_class(drive.usage_percent)]}
                value={drive.usage_percent}
                max="100"
              >
              </progress>
              <span class={[
                "text-xs font-mono w-10 text-right shrink-0",
                usage_text_class(drive.usage_percent)
              ]}>
                {drive.usage_percent}%
              </span>
            </div>
          </div>
        </div>

        <div :if={@db_drive} class="mt-4 pt-4 border-t border-base-content/10">
          <div class="flex items-baseline justify-between mb-1">
            <span class="text-sm font-medium">Database</span>
            <span class="text-xs text-base-content/60 font-mono">
              {format_bytes(@db_drive.used_bytes)} / {format_bytes(@db_drive.total_bytes)}
            </span>
          </div>
          <div class="flex items-center gap-3">
            <progress
              class={["progress h-1.5 flex-1", usage_progress_class(@db_drive.usage_percent)]}
              value={@db_drive.usage_percent}
              max="100"
            >
            </progress>
            <span class={[
              "text-xs font-mono w-10 text-right",
              usage_text_class(@db_drive.usage_percent)
            ]}>
              {@db_drive.usage_percent}%
            </span>
          </div>
          <% db_role = Enum.find(@db_drive.roles, &(&1.label == "Database")) %>
          <code
            :if={db_role}
            class="text-xs truncate-left text-base-content/50 mt-1 block ml-2"
            title={db_role.path}
          >
            <bdo dir="ltr">{db_role.path}</bdo>
          </code>
        </div>
      </div>
    </div>
    """
  end

  defp external_integrations(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">External Integrations</h2>

        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium">TMDB</span>
              <span :if={@config[:tmdb_configured]} class="text-success text-xs">
                configured
              </span>
              <span :if={!@config[:tmdb_configured]} class="text-error text-xs">
                not configured
              </span>
            </div>

            <div :if={@rate_limiter} class="flex items-center gap-3 text-sm">
              <span class="font-mono text-base-content/60">
                {@rate_limiter.used}/{@rate_limiter.total} used
              </span>
            </div>

            <span :if={!@rate_limiter} class="text-sm text-base-content/40">
              rate limiter not started
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp error_summary_card(assigns) do
    ~H"""
    <div
      class="card glass-surface"
      data-testid="error-summary-card"
      id="error-summary-card"
      phx-hook="ErrorReport"
    >
      <div class="card-body">
        <div class="flex justify-between items-start gap-4">
          <h2 class="card-title text-lg">Errors</h2>

          <.button
            :if={@buckets != []}
            variant="outline"
            size="sm"
            phx-click="open_error_report_modal"
          >
            Report errors
          </.button>
        </div>

        <p :if={@buckets == []} class="text-base-content/60">
          No errors in the last hour.
        </p>

        <div :if={@buckets != []} class="mt-1">
          <div class="text-sm text-base-content/70">
            <span class="text-error font-semibold">{total_count(@buckets)}</span>
            errors in the last hour, across {length(@buckets)} distinct issues.
          </div>

          <ul class="mt-2 space-y-1">
            <li :for={bucket <- top_buckets(@buckets)} class="text-sm">
              <span class="font-mono text-xs truncate" title={bucket.display_title}>
                {bucket.display_title}
              </span>
              <.badge variant="ghost" class="ml-1">×{bucket.count}</.badge>
              <span class="text-xs text-base-content/50 ml-1">
                {bucket.component} · {relative_time(bucket.last_seen)}
              </span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp total_count(buckets), do: Enum.reduce(buckets, 0, &(&1.count + &2))

  defp top_buckets(buckets) do
    buckets
    |> Enum.sort_by(& &1.count, :desc)
    |> Enum.take(3)
  end

  defp relative_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      true -> "#{div(diff, 3_600)}h ago"
    end
  end

  defp playback_summary_card(assigns) do
    sessions =
      assigns.playback.sessions
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(fn session -> session[:started_at] || 0 end)

    assigns = assign(assigns, :sessions, sessions)

    ~H"""
    <div class={[
      "card glass-surface border-l-3",
      playback_border_class(@playback.state)
    ]}>
      <div class="card-body">
        <div class="flex justify-between items-center">
          <h2 class="card-title text-lg">Playback</h2>
          <span :if={@sessions == []} class="text-sm text-base-content/60">idle</span>
          <span :if={@sessions != []} class="text-sm text-base-content/60">
            {length(@sessions)} active
          </span>
        </div>

        <div :if={@sessions == []} class="mt-1 text-sm text-base-content/60">Idle</div>

        <div :for={session <- @sessions} class="mt-2">
          <div class="flex items-center gap-2">
            <span class={["text-xs", playback_text_class(session.state)]}>
              {session.state}
            </span>
            <span class="text-base font-medium truncate">
              {now_playing_title(session.now_playing)}
            </span>
          </div>
          <div
            :if={now_playing_detail(session.now_playing)}
            class="text-sm text-base-content/60 truncate"
          >
            {now_playing_detail(session.now_playing)}
          </div>
          <div
            :if={
              session.now_playing[:duration_seconds] != nil &&
                session.now_playing[:duration_seconds] > 0
            }
            class="flex items-center gap-2 mt-1"
          >
            <progress
              class={["progress h-1.5 flex-1", playback_progress_class(session.state)]}
              value={session.now_playing[:position_seconds] || 0}
              max={session.now_playing.duration_seconds}
            >
            </progress>
            <span class="text-xs text-base-content/50 whitespace-nowrap">
              {format_remaining(
                session.now_playing.duration_seconds -
                  (session.now_playing[:position_seconds] || 0)
              )}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Playback State ---

  defp build_playback_state do
    sessions =
      Map.new(MediaCentarr.Playback.Sessions.list(), fn session ->
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
    MediaCentarr.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp fetch_retry_status do
    %{retrying_count: MediaCentarr.Pipeline.ImageQueue.retrying_count()}
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp load_config do
    config = MediaCentarr.Config

    %{
      tmdb_configured: MediaCentarr.Secret.present?(config.get(:tmdb_api_key)),
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

  defp check_dir_health do
    watch_dirs = MediaCentarr.Config.get(:watch_dirs) || []

    Enum.map(watch_dirs, fn dir ->
      image_dir = MediaCentarr.Config.images_dir_for(dir)

      %{
        dir: dir,
        dir_exists: File.dir?(dir),
        image_dir: image_dir,
        image_dir_exists: File.dir?(image_dir)
      }
    end)
  end

  defp find_drive_for_dir(drives, dir) do
    Enum.find(drives, fn drive ->
      Enum.any?(drive.roles, &(&1.path == dir))
    end)
  end

  defp now_playing_title(%{episode_name: _} = now_playing),
    do: now_playing[:entity_name] || now_playing.entity_id

  defp now_playing_title(%{movie_name: name}) when is_binary(name), do: name
  defp now_playing_title(%{entity_name: name}) when is_binary(name), do: name
  defp now_playing_title(now_playing), do: now_playing.entity_id

  defp now_playing_detail(%{episode_name: name} = now_playing) when is_binary(name) do
    if now_playing[:season_number] do
      "S#{now_playing[:season_number]}E#{now_playing[:episode_number] || "?"} · #{name}"
    else
      name
    end
  end

  defp now_playing_detail(_), do: nil
end
