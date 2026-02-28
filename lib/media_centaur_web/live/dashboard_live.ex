defmodule MediaCentaurWeb.DashboardLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Admin, Dashboard}
  alias MediaCentaur.Pipeline.Stats

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "watcher:state")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "playback:events")

        Process.send_after(self(), :tick_pipeline, 1_000)

        stats = Dashboard.fetch_stats()

        pipeline_stats = Stats.get_snapshot()

        socket
        |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
        |> assign(library_stats: stats.library)
        |> assign(pending_review: stats.pending_review)
        |> assign(recent_errors: pipeline_stats.recent_errors)
        |> assign(playback: MediaCentaur.Playback.Manager.current_state())
        |> assign(config: load_config())
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(rate_limiter: fetch_rate_limiter())
      else
        socket
        |> assign(watcher_statuses: [])
        |> assign(library_stats: %{episodes: 0, files: 0, images: 0, by_type: %{}})
        |> assign(pending_review: [])
        |> assign(recent_errors: [])
        |> assign(playback: %{state: :idle, now_playing: nil})
        |> assign(config: %{})
        |> assign(pipeline_stats: Stats.empty_snapshot())
        |> assign(rate_limiter: nil)
      end

    {:ok,
     assign(socket,
       scanning: false,
       clearing_database: false,
       refreshing_images: false,
       stats_timer: nil,
       pipeline_concurrency: MediaCentaur.Pipeline.processor_concurrency()
     )}
  end

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

        stats = Dashboard.fetch_stats()

        socket =
          socket
          |> put_flash(:info, message)
          |> assign(scanning: false)
          |> assign(library_stats: stats.library)

        {:noreply, socket}
    end
  end

  def handle_event("clear_database", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      Admin.clear_database()
      send(liveview, :database_cleared)
    end)

    {:noreply, assign(socket, clearing_database: true)}
  end

  def handle_event("refresh_image_cache", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      {:ok, count} = Admin.refresh_image_cache()
      send(liveview, {:image_cache_refreshed, count})
    end)

    {:noreply, assign(socket, refreshing_images: true)}
  end

  @impl true
  def handle_info(:database_cleared, socket) do
    stats = Dashboard.fetch_stats()

    {:noreply,
     socket
     |> assign(clearing_database: false)
     |> assign(library_stats: stats.library)
     |> assign(pending_review: stats.pending_review)
     |> assign(recent_errors: stats.recent_errors)
     |> put_flash(:info, "Database cleared successfully")}
  end

  def handle_info({:image_cache_refreshed, count}, socket) do
    stats = Dashboard.fetch_stats()

    {:noreply,
     socket
     |> assign(refreshing_images: false)
     |> assign(library_stats: stats.library)
     |> assign(pending_review: stats.pending_review)
     |> assign(recent_errors: stats.recent_errors)
     |> put_flash(:info, "Image cache refreshed — re-downloaded images for #{count} entities")}
  end

  @impl true
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
     |> assign(pending_review: stats.pending_review)
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

  def handle_info(:tick_pipeline, socket) do
    Process.send_after(self(), :tick_pipeline, 1_000)
    pipeline_stats = Stats.get_snapshot()

    {:noreply,
     socket
     |> assign(pipeline_stats: pipeline_stats)
     |> assign(recent_errors: pipeline_stats.recent_errors)
     |> assign(rate_limiter: fetch_rate_limiter())}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/">
      <div class="space-y-6">
        <div class="flex items-center justify-between">
          <h1 class="text-2xl font-bold">Dashboard</h1>
          <button
            phx-click="scan"
            disabled={@scanning}
            class="btn btn-primary btn-sm"
          >
            {if @scanning, do: "Scanning…", else: "Scan directories"}
          </button>
        </div>

        <div class="grid lg:grid-cols-2 gap-6">
          <div class="lg:col-span-2"><.library_stats stats={@library_stats} /></div>
          <div class="lg:col-span-2">
            <.pipeline_status stats={@pipeline_stats} pipeline_concurrency={@pipeline_concurrency} />
          </div>
          <.external_integrations rate_limiter={@rate_limiter} config={@config} />
          <.watcher_health statuses={@watcher_statuses} />
          <.playback_status playback={@playback} />
          <.config_overview config={@config} />
          <div class="lg:col-span-2"><.pending_review_table files={@pending_review} /></div>
          <div class="lg:col-span-2"><.recent_errors_table files={@recent_errors} /></div>
          <div class="lg:col-span-2">
            <.danger_zone
              clearing_database={@clearing_database}
              refreshing_images={@refreshing_images}
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp library_stats(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Library</h2>

        <div class="stats stats-horizontal bg-base-200 w-full">
          <div class="stat">
            <div class="stat-title">Movies</div>
            <div class="stat-value text-2xl">{@stats.by_type[:movie] || 0}</div>
            <div class="stat-desc">{@stats.by_type[:movie_series] || 0} collections</div>
          </div>
          <div class="stat">
            <div class="stat-title">TV Series</div>
            <div class="stat-value text-2xl">{@stats.by_type[:tv_series] || 0}</div>
            <div class="stat-desc">{@stats.episodes} episodes</div>
          </div>
          <div :if={(@stats.by_type[:video_object] || 0) > 0} class="stat">
            <div class="stat-title">Videos</div>
            <div class="stat-value text-2xl">{@stats.by_type[:video_object]}</div>
          </div>
        </div>

        <div class="flex gap-4 text-sm text-base-content/60 px-1">
          <span>{@stats.files} files tracked</span>
          <span>{@stats.images} images cached</span>
        </div>
      </div>
    </div>
    """
  end

  defp pipeline_status(assigns) do
    assigns =
      assign(assigns, :stage_order, [:parse, :search, :fetch_metadata, :download_images, :ingest])

    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Pipeline</h2>
          <div class="flex items-center gap-3 text-sm">
            <span :if={@stats.queue_depth > 0} class="badge badge-info badge-sm">
              {@stats.queue_depth} queued
            </span>
            <span class="text-base-content/60">
              {if @stats.total_processed > 0,
                do: "#{@stats.total_processed} processed",
                else: "idle"}
            </span>
            <span :if={@stats.total_failed > 0} class="text-error text-xs">
              {@stats.total_failed} failed
            </span>
          </div>
        </div>

        <div class="space-y-2 mt-2">
          <.pipeline_stage
            :for={stage <- @stage_order}
            stage={stage}
            data={@stats.stages[stage]}
            concurrency={@pipeline_concurrency}
            needs_review_count={@stats.needs_review_count}
          />
        </div>
      </div>
    </div>
    """
  end

  defp pipeline_stage(assigns) do
    ~H"""
    <div
      class="grid items-center gap-3 py-1"
      style="grid-template-columns: 0.5rem 8rem 5.5rem 5rem 5rem 2.5rem 1fr"
    >
      <span class={["w-2 h-2 rounded-full", stage_dot_class(@data.status)]}></span>

      <span class="text-sm font-medium truncate">{stage_display_name(@stage)}</span>

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

      <span class="text-xs text-base-content/40 truncate">
        <span :if={@stage == :search && @needs_review_count > 0}>
          {@needs_review_count} sent to review
        </span>
        <span :if={@data.last_error} class="text-error">
          {elem(@data.last_error, 0)}
        </span>
        <span :if={@data.status == :idle and !@data.last_error}>
          {stage_description(@stage)}
        </span>
      </span>
    </div>
    """
  end

  defp stage_description(:parse), do: "Extract title, year, season from filename"
  defp stage_description(:search), do: "Find matching TMDB entry"
  defp stage_description(:fetch_metadata), do: "Fetch full details from TMDB"
  defp stage_description(:download_images), do: "Download poster, backdrop, logo artwork"
  defp stage_description(:ingest), do: "Create or update library entity"

  defp external_integrations(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
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

  defp watcher_health(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
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

  defp playback_status(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Playback</h2>

        <div class="flex items-center gap-3">
          <span class={["badge", playback_badge_class(@playback.state)]}>
            {@playback.state}
          </span>

          <span :if={@playback.now_playing} class="text-sm">
            <span class="font-mono">{@playback.now_playing.entity_id}</span>
            <span :if={
              @playback.now_playing[:duration_seconds] && @playback.now_playing.duration_seconds > 0
            }>
              — {format_seconds(@playback.now_playing[:position_seconds] || 0)} / {format_seconds(
                @playback.now_playing.duration_seconds
              )}
            </span>
          </span>

          <span :if={!@playback.now_playing} class="text-sm text-base-content/60">
            Nothing playing
          </span>
        </div>
      </div>
    </div>
    """
  end

  defp pending_review_table(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">
            Pending Review
            <span :if={@files != []} class="badge badge-warning badge-sm">{length(@files)}</span>
          </h2>
          <.link :if={@files != []} navigate="/review" class="link link-primary text-sm">
            Review all &rarr;
          </.link>
        </div>

        <p :if={@files == []} class="text-base-content/60">No files awaiting review.</p>

        <div :if={@files != []} class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>File</th>
                <th>Parsed Title</th>
                <th>Confidence</th>
                <th>Detected At</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={file <- @files}>
                <td class="font-mono text-xs max-w-xs truncate">{Path.basename(file.file_path)}</td>
                <td>{file.parsed_title || "—"}</td>
                <td>
                  <span
                    :if={file.confidence}
                    class={["badge badge-sm", confidence_badge_class(file.confidence)]}
                  >
                    {Float.round(file.confidence, 2)}
                  </span>
                  <span :if={!file.confidence} class="text-base-content/40">—</span>
                </td>
                <td class="text-xs">{format_datetime(file.inserted_at)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
    """
  end

  defp recent_errors_table(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
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
                <td class="font-mono text-xs max-w-xs truncate">
                  {Path.basename(error.file_path || "")}
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

  defp config_overview(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Configuration</h2>

        <div :if={@config == %{}} class="text-base-content/60">Loading...</div>

        <div :if={@config != %{}} class="grid grid-cols-1 sm:grid-cols-2 gap-x-8 gap-y-2 text-sm">
          <div class="flex justify-between">
            <span class="text-base-content/60">Auto-approve threshold</span>
            <span class="font-mono">{@config[:auto_approve_threshold] || "—"}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/60">MPV path</span>
            <span class="font-mono">{@config[:mpv_path] || "—"}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/60">Images directory</span>
            <span class="font-mono text-xs truncate max-w-48">
              {@config[:media_images_dir] || "—"}
            </span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/60">Database path</span>
            <span class="font-mono text-xs truncate max-w-48">{@config[:database_path] || "—"}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-base-content/60">Watch directories</span>
            <span class="font-mono">{@config[:watch_dirs_count] || 0}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp danger_zone(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm border border-error/20">
      <div class="card-body">
        <h2 class="card-title text-lg text-error">Danger Zone</h2>
        <div class="flex flex-wrap gap-3">
          <button
            phx-click="clear_database"
            disabled={@clearing_database}
            data-confirm="This will permanently delete ALL entities, files, images, and progress. This cannot be undone. Continue?"
            class="btn btn-error btn-sm btn-outline"
          >
            {if @clearing_database, do: "Clearing...", else: "Clear database"}
          </button>
          <button
            phx-click="refresh_image_cache"
            disabled={@refreshing_images}
            data-confirm="This will delete all cached artwork and re-download from TMDB. This may take a while. Continue?"
            class="btn btn-warning btn-sm btn-outline"
          >
            {if @refreshing_images, do: "Refreshing...", else: "Clear & refresh image cache"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp debounce_stats_refresh(socket) do
    if socket.assigns[:stats_timer] do
      Process.cancel_timer(socket.assigns.stats_timer)
    end

    timer = Process.send_after(self(), :refresh_stats, 1_000)
    assign(socket, stats_timer: timer)
  end

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  # --- Helpers ---

  defp format_datetime(nil), do: "—"

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  end

  defp format_seconds(nil), do: "0:00"

  defp format_seconds(seconds) when is_number(seconds) do
    total = trunc(seconds)
    mins = div(total, 60)
    secs = rem(total, 60)
    "#{mins}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  defp load_config do
    config = MediaCentaur.Config

    %{
      tmdb_configured: config.get(:tmdb_api_key) not in [nil, ""],
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      media_images_dir: config.get(:media_images_dir),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

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

  defp stage_display_name(:parse), do: "Parse"
  defp stage_display_name(:search), do: "Search"
  defp stage_display_name(:fetch_metadata), do: "Fetch Metadata"
  defp stage_display_name(:download_images), do: "Download Images"
  defp stage_display_name(:ingest), do: "Ingest"

  defp format_throughput(rate) when rate == 0.0, do: "—"
  defp format_throughput(rate), do: "#{rate}/s"

  defp format_duration(nil), do: "—"
  defp format_duration(ms) when ms < 1_000, do: "#{round(ms)}ms"
  defp format_duration(ms) when ms < 60_000, do: "#{Float.round(ms / 1_000, 1)}s"
  defp format_duration(ms), do: "#{Float.round(ms / 60_000, 1)}m"

  defp watcher_badge_class(:watching), do: "badge-success"
  defp watcher_badge_class(:initializing), do: "badge-warning"
  defp watcher_badge_class(_), do: "badge-error"

  defp playback_badge_class(:idle), do: "badge-ghost"
  defp playback_badge_class(:playing), do: "badge-success"
  defp playback_badge_class(:paused), do: "badge-warning"
  defp playback_badge_class(_), do: "badge-info"

  defp confidence_badge_class(score) when score >= 0.8, do: "badge-success"
  defp confidence_badge_class(score) when score >= 0.5, do: "badge-warning"
  defp confidence_badge_class(_), do: "badge-error"
end
