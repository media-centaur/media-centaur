defmodule MediaCentaurWeb.DashboardLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Dashboard, Storage}
  alias MediaCentaur.Pipeline.Stats
  alias MediaCentaur.ImagePipeline

  @storage_refresh_ms 5 * 60 * 1_000

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "watcher:state")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")

        Process.send_after(self(), :tick_pipeline, 1_000)
        Process.send_after(self(), :refresh_storage, @storage_refresh_ms)

        stats = Dashboard.fetch_stats()
        pipeline_stats = Stats.get_snapshot()
        image_stats = ImagePipeline.Stats.get_snapshot()

        socket
        |> assign(library_stats: stats.library)
        |> assign(pending_review_count: length(stats.pending_review))
        |> assign(recent_errors: merge_recent_errors(pipeline_stats, image_stats))
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(image_pipeline_stats: image_stats)
        |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
        |> assign(storage_drives: Storage.measure_all())
        |> assign(config: load_config())
        |> assign(rate_limiter: fetch_rate_limiter())
        |> assign(retry_status: fetch_retry_status())
        |> assign(playback: MediaCentaur.Playback.Manager.current_state())
      else
        socket
        |> assign(library_stats: %{episodes: 0, files: 0, images: 0, by_type: %{}})
        |> assign(pending_review_count: 0)
        |> assign(recent_errors: [])
        |> assign(pipeline_stats: Stats.empty_snapshot())
        |> assign(image_pipeline_stats: ImagePipeline.Stats.empty_snapshot())
        |> assign(watcher_statuses: [])
        |> assign(storage_drives: [])
        |> assign(config: %{})
        |> assign(rate_limiter: nil)
        |> assign(retry_status: nil)
        |> assign(playback: %{state: :idle, now_playing: nil})
      end

    {:ok,
     assign(socket,
       scanning: false,
       stats_timer: nil,
       pipeline_concurrency: MediaCentaur.Pipeline.processor_concurrency(),
       image_pipeline_concurrency: 4
     )}
  end

  # --- Events ---

  @impl true
  def handle_event("scan", _params, socket) do
    socket = assign(socket, scanning: true)

    case MediaCentaur.Watcher.Supervisor.scan() do
      {:ok, count} ->
        message =
          case count do
            0 -> "Scan complete — no new files found"
            1 -> "Scan complete — 1 new file detected"
            n -> "Scan complete — #{n} new files detected"
          end

        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(scanning: false)}
    end
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
     |> assign(recent_errors: merge_recent_errors(pipeline_stats, image_stats))
     |> assign(rate_limiter: fetch_rate_limiter())
     |> assign(retry_status: fetch_retry_status())}
  end

  def handle_info(:refresh_storage, socket) do
    Process.send_after(self(), :refresh_storage, @storage_refresh_ms)
    {:noreply, assign(socket, storage_drives: Storage.measure_all())}
  end

  def handle_info({:watcher_state_changed, _dir, _new_state}, socket) do
    {:noreply, assign(socket, watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())}
  end

  def handle_info({:entities_changed, _entity_ids}, socket) do
    {:noreply, debounce_stats_refresh(socket)}
  end

  def handle_info(:refresh_stats, socket) do
    stats = Dashboard.fetch_stats()

    {:noreply,
     socket
     |> assign(stats_timer: nil)
     |> assign(library_stats: stats.library)
     |> assign(pending_review_count: length(stats.pending_review))
     |> assign(recent_errors: stats.recent_errors)}
  end

  def handle_info({:playback_state_changed, new_state, now_playing}, socket) do
    {:noreply, assign(socket, playback: %{state: new_state, now_playing: now_playing})}
  end

  def handle_info({:playback_progress, progress}, socket) do
    playback = socket.assigns.playback

    now_playing =
      if playback.now_playing do
        playback.now_playing
        |> Map.put(:position_seconds, progress.position_seconds)
        |> Map.put(:duration_seconds, progress.duration_seconds)
      end

    {:noreply, assign(socket, playback: %{playback | now_playing: now_playing})}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/">
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-6">
        <h1 class="text-2xl font-bold sm:col-span-2">Dashboard</h1>

        <div class="sm:col-span-2">
          <.library_stats stats={@library_stats} />
        </div>

        <div class="sm:col-span-2">
          <.pipeline_card
            content_stats={@pipeline_stats}
            image_stats={@image_pipeline_stats}
            retry_status={@retry_status}
            pipeline_concurrency={@pipeline_concurrency}
            image_concurrency={@image_pipeline_concurrency}
            scanning={@scanning}
          />
        </div>

        <.watcher_health statuses={@watcher_statuses} />
        <.external_integrations rate_limiter={@rate_limiter} config={@config} />

        <div class="sm:col-span-2">
          <.recent_errors_table files={@recent_errors} />
        </div>

        <div class="sm:col-span-2">
          <.storage_health drives={@storage_drives} />
        </div>

        <.review_summary_card count={@pending_review_count} />
        <.playback_summary_card playback={@playback} />
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp library_stats(assigns) do
    ~H"""
    <div class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3">
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.by_type[:movie] || 0}</div>
        <div class="text-sm text-base-content/60">Movies</div>
        <div class="text-xs text-base-content/40 mt-1">
          {@stats.by_type[:movie_series] || 0} collections
        </div>
      </div>
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.by_type[:tv_series] || 0}</div>
        <div class="text-sm text-base-content/60">TV Series</div>
        <div class="text-xs text-base-content/40 mt-1">{@stats.episodes} episodes</div>
      </div>
      <div :if={(@stats.by_type[:video_object] || 0) > 0} class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.by_type[:video_object]}</div>
        <div class="text-sm text-base-content/60">Videos</div>
      </div>
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.files}</div>
        <div class="text-sm text-base-content/60">Files Tracked</div>
      </div>
      <div class="p-4 rounded-lg glass-surface">
        <div class="text-2xl font-bold">{@stats.images}</div>
        <div class="text-sm text-base-content/60">Images Cached</div>
      </div>
    </div>
    """
  end

  @stage_grid_columns "grid-template-columns: 0.5rem 11rem 5.5rem 4.5rem 4.5rem 3rem"

  defp pipeline_card(assigns) do
    assigns =
      assigns
      |> assign(:stage_order, [:parse, :search, :fetch_metadata, :ingest])
      |> assign(:grid_columns, @stage_grid_columns)

    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <%!-- Pipeline header --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Pipeline</h2>
          <div class="flex items-center gap-3 text-sm">
            <span :if={@content_stats.queue_depth > 0} class="badge badge-info badge-sm">
              {@content_stats.queue_depth} queued
            </span>
            <span :if={@content_stats.total_failed > 0} class="text-error text-xs">
              {@content_stats.total_failed} failed
            </span>
            <button
              phx-click="scan"
              disabled={@scanning}
              class="btn btn-primary btn-xs"
            >
              {if @scanning, do: "Scanning…", else: "Scan directories"}
            </button>
          </div>
        </div>

        <%!-- Column headers --%>
        <div
          class="grid items-center gap-3 mt-3 mb-1"
          style={@grid_columns}
        >
          <span></span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide">Stage</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide">Status</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Rate</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Avg</span>
          <span class="text-xs text-base-content/40 uppercase tracking-wide text-right">Slots</span>
        </div>

        <%!-- New Media section --%>
        <h3 class="text-xs text-base-content/50 uppercase tracking-wide mt-1">New Media</h3>

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
          class="grid items-center gap-3 py-1"
          style={@grid_columns}
        >
          <span class={["w-2 h-2 rounded-full", stage_dot_class(@image_stats.status)]}></span>

          <span class="text-sm font-medium truncate">
            Download + Resize
            <span :if={@image_stats.last_error} class="text-error text-xs font-normal ml-2">
              {elem(@image_stats.last_error, 0)}
            </span>
          </span>

          <span class={["badge badge-xs", stage_badge_class(@image_stats.status)]}>
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
      class="grid items-center gap-3 py-1"
      style={@grid_columns}
    >
      <span class={["w-2 h-2 rounded-full", stage_dot_class(@data.status)]}></span>

      <span class="text-sm font-medium truncate">
        {stage_display_name(@stage)}
        <span :if={@data.last_error} class="text-error text-xs font-normal ml-2">
          {elem(@data.last_error, 0)}
        </span>
      </span>

      <span class={["badge badge-xs", stage_badge_class(@data.status)]}>
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

  defp watcher_health(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Watcher Health</h2>

        <p :if={@statuses == []} class="text-base-content/60">No watch directories configured.</p>

        <ul :if={@statuses != []} class="space-y-2">
          <li :for={status <- @statuses} class="flex items-center gap-3">
            <span class={["badge badge-sm", watcher_badge_class(status.state)]}>
              {status.state}
            </span>
            <code class="text-sm">{status.dir}</code>
          </li>
        </ul>
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
              <span :if={@config[:tmdb_configured]} class="badge badge-success badge-xs">
                configured
              </span>
              <span :if={!@config[:tmdb_configured]} class="badge badge-error badge-xs">
                not configured
              </span>
            </div>

            <div :if={@rate_limiter} class="flex items-center gap-3 text-sm">
              <span class="font-mono text-base-content/60">
                {@rate_limiter.used}/{@rate_limiter.total} used
              </span>
              <span class={[
                "font-mono",
                if(@rate_limiter.available == 0, do: "text-warning", else: "text-success")
              ]}>
                {@rate_limiter.available} available
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

  defp recent_errors_table(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">
          Recent Errors
          <span :if={@files != []} class="badge badge-error badge-sm">{length(@files)}</span>
        </h2>

        <p :if={@files == []} class="text-base-content/60">No errors.</p>

        <div :if={@files != []} class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Stage</th>
                <th>File</th>
                <th>Error Message</th>
                <th>Time</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={error <- @files}>
                <td>
                  <span class="badge badge-error badge-xs">{error[:stage] || "—"}</span>
                </td>
                <td class="font-mono text-xs max-w-xs truncate-left" title={error.file_path}>
                  {error.file_path || "—"}
                </td>
                <td class="text-error text-xs max-w-md truncate">{error.error_message || "—"}</td>
                <td class="text-xs">{format_datetime(error.updated_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp storage_health(assigns) do
    ~H"""
    <div class="card glass-surface">
      <div class="card-body">
        <h2 class="card-title text-lg">Storage</h2>

        <p :if={@drives == []} class="text-base-content/60">No directories configured.</p>

        <div :if={@drives != []} class="space-y-6">
          <div :for={drive <- @drives}>
            <div class="flex items-baseline justify-between mb-1">
              <span class="text-sm font-medium">
                {drive.mount_point}
                <span class="text-base-content/40 font-normal">({drive.device})</span>
              </span>
              <span class="text-xs text-base-content/60 font-mono">
                {format_bytes(drive.used_bytes)} / {format_bytes(drive.total_bytes)}
              </span>
            </div>
            <div class="flex items-center gap-3 mb-3">
              <progress
                class={["progress flex-1", usage_progress_class(drive.usage_percent)]}
                value={drive.usage_percent}
                max="100"
              >
              </progress>
              <span class={[
                "text-sm font-mono w-10 text-right",
                usage_text_class(drive.usage_percent)
              ]}>
                {drive.usage_percent}%
              </span>
            </div>
            <div class="space-y-1 ml-2">
              <div
                :for={role <- drive.roles}
                class="grid gap-3 text-xs"
                style="grid-template-columns: 6rem 1fr"
              >
                <span class="text-base-content/50">{role.label}</span>
                <code
                  class="truncate-left text-base-content/70"
                  title={role.path}
                >
                  {role.path}
                </code>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp review_summary_card(assigns) do
    ~H"""
    <.link
      navigate="/review"
      class={[
        "card glass-surface hover:shadow-md transition-shadow border-l-3",
        if(@count > 0, do: "border-warning", else: "border-base-content/20")
      ]}
    >
      <div class="card-body">
        <h2 class="card-title text-lg">Review</h2>

        <div class="text-sm">
          <span :if={@count == 0} class="text-base-content/60">No files pending review</span>
          <div :if={@count > 0} class="flex items-center gap-2">
            <span class="badge badge-warning badge-sm">{@count}</span>
            <span>files awaiting review</span>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp playback_summary_card(assigns) do
    ~H"""
    <div class={[
      "card glass-surface border-l-3",
      playback_border_class(@playback.state)
    ]}>
      <div class="card-body">
        <h2 class="card-title text-lg">Playback</h2>

        <div class="text-sm">
          <div class="flex items-center gap-2">
            <span class={["badge badge-sm", playback_badge_class(@playback.state)]}>
              {@playback.state}
            </span>

            <span :if={@playback.now_playing} class="truncate">
              {now_playing_label(@playback.now_playing)}
            </span>
            <span :if={!@playback.now_playing} class="text-base-content/60">Idle</span>
          </div>

          <div
            :if={
              @playback.now_playing &&
                @playback.now_playing[:duration_seconds] &&
                @playback.now_playing.duration_seconds > 0
            }
            class="mt-1 text-xs text-base-content/60"
          >
            {format_seconds(@playback.now_playing[:position_seconds] || 0)} / {format_seconds(
              @playback.now_playing.duration_seconds
            )}
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp merge_recent_errors(content_stats, image_stats) do
    (content_stats.recent_errors ++ image_stats.recent_errors)
    |> Enum.sort_by(& &1.updated_at, {:desc, DateTime})
    |> Enum.take(50)
  end

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp fetch_retry_status do
    MediaCentaur.ImagePipeline.RetryScheduler.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp load_config do
    config = MediaCentaur.Config

    %{
      tmdb_configured: config.get(:tmdb_api_key) not in [nil, ""],
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

  defp format_datetime(nil), do: "—"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp format_throughput(rate) when rate == 0.0, do: "—"
  defp format_throughput(rate), do: "#{rate}/s"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1_000, do: "#{round(ms)}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  defp stage_dot_class(:idle), do: "bg-base-content/20"
  defp stage_dot_class(:active), do: "bg-success"
  defp stage_dot_class(:saturated), do: "bg-warning"
  defp stage_dot_class(:erroring), do: "bg-error"

  defp stage_badge_class(:idle), do: "badge-ghost"
  defp stage_badge_class(:active), do: "badge-success"
  defp stage_badge_class(:saturated), do: "badge-warning"
  defp stage_badge_class(:erroring), do: "badge-error"

  defp stage_status_label(:idle), do: "idle"
  defp stage_status_label(:active), do: "active"
  defp stage_status_label(:saturated), do: "saturated"
  defp stage_status_label(:erroring), do: "erroring"

  defp stage_display_name(:parse), do: "Parse Media Path"
  defp stage_display_name(:search), do: "Match on TMDB"
  defp stage_display_name(:fetch_metadata), do: "Enrich Metadata"
  defp stage_display_name(:ingest), do: "Add to Library"

  defp watcher_badge_class(:watching), do: "badge-success"
  defp watcher_badge_class(:initializing), do: "badge-warning"
  defp watcher_badge_class(_), do: "badge-error"

  defp playback_badge_class(:idle), do: "badge-ghost"
  defp playback_badge_class(:playing), do: "badge-success"
  defp playback_badge_class(:paused), do: "badge-warning"
  defp playback_badge_class(_), do: "badge-info"

  defp now_playing_label(%{episode_name: name} = np) when is_binary(name) do
    "S#{np[:season_number] || "?"}E#{np[:episode_number] || "?"} · #{name}"
  end

  defp now_playing_label(%{movie_name: name}) when is_binary(name), do: name

  defp now_playing_label(%{entity_name: name}) when is_binary(name), do: name

  defp now_playing_label(np), do: np.entity_id

  defp playback_border_class(:playing), do: "border-success"
  defp playback_border_class(:paused), do: "border-warning"
  defp playback_border_class(_), do: "border-base-content/20"

  @gib Float.pow(1024.0, 3)
  @tib Float.pow(1024.0, 4)

  defp format_bytes(bytes) when bytes >= @tib do
    "#{Float.round(bytes / @tib, 1)} TiB"
  end

  defp format_bytes(bytes) do
    "#{Float.round(bytes / @gib, 1)} GiB"
  end

  defp usage_progress_class(percent) when percent >= 90, do: "progress-error"
  defp usage_progress_class(percent) when percent >= 75, do: "progress-warning"
  defp usage_progress_class(_percent), do: "progress-success"

  defp usage_text_class(percent) when percent >= 90, do: "text-error"
  defp usage_text_class(percent) when percent >= 75, do: "text-warning"
  defp usage_text_class(_percent), do: "text-success"
end
