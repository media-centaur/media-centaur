defmodule MediaCentaurWeb.OperationsLive do
  use MediaCentaurWeb, :live_view

  alias MediaCentaur.{Admin, Dashboard, Log, Storage}
  alias MediaCentaur.Library.Image
  alias MediaCentaur.Pipeline.Stats

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "watcher:state")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaCentaur.PubSub, "logging:updates")

        Process.send_after(self(), :tick_pipeline, 1_000)

        pipeline_stats = Stats.get_snapshot()
        {enabled, all} = Log.status()

        socket
        |> assign(watcher_statuses: MediaCentaur.Watcher.Supervisor.statuses())
        |> assign(recent_errors: pipeline_stats.recent_errors)
        |> assign(incomplete_images: Ash.read!(Image, action: :incomplete))
        |> assign(storage_health: Storage.measure_all())
        |> assign(config: load_config())
        |> assign(pipeline_stats: pipeline_stats)
        |> assign(rate_limiter: fetch_rate_limiter())
        |> assign(enabled_components: enabled)
        |> assign(all_components: all)
        |> assign(suppressed_frameworks: Log.suppressed_frameworks())
      else
        socket
        |> assign(watcher_statuses: [])
        |> assign(recent_errors: [])
        |> assign(incomplete_images: [])
        |> assign(storage_health: [])
        |> assign(config: %{})
        |> assign(pipeline_stats: Stats.empty_snapshot())
        |> assign(rate_limiter: nil)
        |> assign(enabled_components: [])
        |> assign(all_components: [])
        |> assign(suppressed_frameworks: [])
      end

    {:ok,
     assign(socket,
       scanning: false,
       clearing_database: false,
       refreshing_images: false,
       retrying_images: false,
       stats_timer: nil,
       pipeline_concurrency: MediaCentaur.Pipeline.processor_concurrency()
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

  def handle_event("toggle_component", %{"component" => component}, socket) do
    component = String.to_existing_atom(component)

    if component in socket.assigns.enabled_components do
      Log.disable(component)
    else
      Log.enable(component)
    end

    {:noreply, assign_log_state(socket)}
  end

  def handle_event("enable_all", _params, socket) do
    Log.all()
    {:noreply, assign_log_state(socket)}
  end

  def handle_event("disable_all", _params, socket) do
    Log.none()
    {:noreply, assign_log_state(socket)}
  end

  def handle_event("toggle_framework", %{"key" => key}, socket) do
    key = String.to_existing_atom(key)

    if key in socket.assigns.suppressed_frameworks do
      Log.unsuppress_framework(key)
    else
      Log.suppress_framework(key)
    end

    {:noreply, assign_log_state(socket)}
  end

  def handle_event("retry_incomplete_images", _params, socket) do
    liveview = self()

    Task.Supervisor.start_child(MediaCentaur.TaskSupervisor, fn ->
      {:ok, result} = Admin.retry_incomplete_images()
      send(liveview, {:incomplete_images_retried, result})
    end)

    {:noreply, assign(socket, retrying_images: true)}
  end

  def handle_event("dismiss_incomplete_images", _params, socket) do
    {:ok, count} = Admin.dismiss_incomplete_images()

    {:noreply,
     socket
     |> assign(incomplete_images: [])
     |> put_flash(:info, "Dismissed #{count} incomplete images")}
  end

  # --- Info handlers ---

  @impl true
  def handle_info(:database_cleared, socket) do
    {:noreply,
     socket
     |> assign(clearing_database: false)
     |> put_flash(:info, "Database cleared successfully")}
  end

  def handle_info({:image_cache_refreshed, count}, socket) do
    {:noreply,
     socket
     |> assign(refreshing_images: false)
     |> put_flash(:info, "Image cache refreshed — re-downloaded images for #{count} entities")}
  end

  def handle_info({:incomplete_images_retried, result}, socket) do
    {:noreply,
     socket
     |> assign(retrying_images: false)
     |> assign(incomplete_images: Ash.read!(Image, action: :incomplete))
     |> put_flash(:info, "Retried #{result.retried} incomplete images")}
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
     |> assign(recent_errors: stats.recent_errors)
     |> assign(incomplete_images: Ash.read!(Image, action: :incomplete))}
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

  def handle_info(:log_settings_changed, socket) do
    {:noreply, assign_log_state(socket)}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_path="/operations">
      <div class="space-y-6">
        <h1 class="text-2xl font-bold">Operations</h1>

        <.pipeline_status
          stats={@pipeline_stats}
          pipeline_concurrency={@pipeline_concurrency}
          scanning={@scanning}
        />
        <.watcher_health statuses={@watcher_statuses} />
        <.recent_errors_table files={@recent_errors} />
        <.incomplete_images_card
          images={@incomplete_images}
          retrying={@retrying_images}
        />
        <.storage_health usages={@storage_health} />
        <.external_integrations rate_limiter={@rate_limiter} config={@config} />
        <.config_overview config={@config} />
        <.thinking_logs enabled={@enabled_components} all={@all_components} />
        <.framework_logs suppressed={@suppressed_frameworks} />
        <.danger_zone
          clearing_database={@clearing_database}
          refreshing_images={@refreshing_images}
        />
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

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
            <button
              phx-click="scan"
              disabled={@scanning}
              class="btn btn-primary btn-xs"
            >
              {if @scanning, do: "Scanning…", else: "Scan directories"}
            </button>
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

  defp incomplete_images_card(assigns) do
    ~H"""
    <div :if={@images != []} class="card bg-base-100 shadow-sm border border-warning/20">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">
            Incomplete Images <span class="badge badge-warning badge-sm">{length(@images)}</span>
          </h2>
          <div class="flex gap-2">
            <button
              phx-click="retry_incomplete_images"
              disabled={@retrying}
              class="btn btn-sm btn-primary"
            >
              {if @retrying, do: "Retrying…", else: "Retry all"}
            </button>
            <button
              phx-click="dismiss_incomplete_images"
              data-confirm="This will delete all incomplete image records. The images will need to be re-fetched through the pipeline. Continue?"
              class="btn btn-sm btn-outline btn-warning"
            >
              Dismiss all
            </button>
          </div>
        </div>

        <p class="text-sm text-base-content/60">
          Images with a TMDB URL that were never successfully downloaded.
        </p>

        <div class="overflow-x-auto">
          <table class="table table-sm table-zebra">
            <thead>
              <tr>
                <th>Entity</th>
                <th>Role</th>
                <th>URL</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={image <- @images}>
                <td class="text-sm max-w-xs truncate">
                  {if image.entity, do: image.entity.name, else: "—"}
                </td>
                <td>
                  <span class="badge badge-ghost badge-xs">{image.role}</span>
                </td>
                <td class="font-mono text-xs max-w-md truncate">{image.url}</td>
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
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Storage</h2>

        <p :if={@usages == []} class="text-base-content/60">No directories configured.</p>

        <div :if={@usages != []} class="space-y-4">
          <div :for={usage <- @usages}>
            <div class="flex items-baseline justify-between mb-1">
              <div>
                <span class="text-sm font-medium">{usage.label}</span>
                <code :if={usage.label != usage.path} class="text-xs text-base-content/40 ml-2">
                  {usage.path}
                </code>
              </div>
              <span class="text-xs text-base-content/60 font-mono">
                {format_bytes(usage.used_bytes)} / {format_bytes(usage.total_bytes)}
              </span>
            </div>
            <div class="flex items-center gap-3">
              <progress
                class={["progress flex-1", usage_progress_class(usage.usage_percent)]}
                value={usage.usage_percent}
                max="100"
              >
              </progress>
              <span class={[
                "text-sm font-mono w-10 text-right",
                usage_text_class(usage.usage_percent)
              ]}>
                {usage.usage_percent}%
              </span>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

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

  defp thinking_logs(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Thinking Logs</h2>
          <div class="flex gap-2">
            <button phx-click="enable_all" class="btn btn-xs btn-outline btn-success">
              Enable all
            </button>
            <button phx-click="disable_all" class="btn btn-xs btn-outline">
              Disable all
            </button>
          </div>
        </div>

        <p class="text-sm text-base-content/60">
          Per-component decision logs. Enable a component to see its thinking in the terminal.
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mt-2">
          <div
            :for={component <- @all}
            class="flex items-center justify-between p-3 rounded-lg bg-base-200"
          >
            <div>
              <span class="font-medium">{component}</span>
              <p class="text-xs text-base-content/50">{component_description(component)}</p>
            </div>
            <input
              type="checkbox"
              class="toggle toggle-sm toggle-success"
              checked={component in @enabled}
              phx-click="toggle_component"
              phx-value-component={component}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp framework_logs(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Framework Logs</h2>

        <p class="text-sm text-base-content/60">
          Suppress noisy library output at runtime. Suppressed modules only emit warning and above.
        </p>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-2">
          <div
            :for={{key, _mod} <- Log.framework_modules()}
            class="flex items-center justify-between p-3 rounded-lg bg-base-200"
          >
            <div>
              <span class="font-medium">{framework_label(key)}</span>
              <p class="text-xs text-base-content/50">{framework_description(key)}</p>
            </div>
            <label class="flex items-center gap-2 cursor-pointer">
              <span class={[
                "text-xs",
                if(key in @suppressed, do: "text-warning", else: "text-success")
              ]}>
                {if key in @suppressed, do: "suppressed", else: "active"}
              </span>
              <input
                type="checkbox"
                class="toggle toggle-sm toggle-warning"
                checked={key in @suppressed}
                phx-click="toggle_framework"
                phx-value-key={key}
              />
            </label>
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

  # --- Private helpers ---

  defp assign_log_state(socket) do
    {enabled, all} = Log.status()

    socket
    |> assign(enabled_components: enabled)
    |> assign(all_components: all)
    |> assign(suppressed_frameworks: Log.suppressed_frameworks())
  end

  defp fetch_rate_limiter do
    MediaCentaur.TMDB.RateLimiter.status()
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
      media_images_dir: config.get(:media_images_dir),
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

  defp stage_display_name(:parse), do: "Parse"
  defp stage_display_name(:search), do: "Search"
  defp stage_display_name(:fetch_metadata), do: "Fetch Metadata"
  defp stage_display_name(:download_images), do: "Download Images"
  defp stage_display_name(:ingest), do: "Ingest"

  defp stage_description(:parse), do: "Extract title, year, season from filename"
  defp stage_description(:search), do: "Find matching TMDB entry"
  defp stage_description(:fetch_metadata), do: "Fetch full details from TMDB"
  defp stage_description(:download_images), do: "Download poster, backdrop, logo artwork"
  defp stage_description(:ingest), do: "Create or update library entity"

  defp watcher_badge_class(:watching), do: "badge-success"
  defp watcher_badge_class(:initializing), do: "badge-warning"
  defp watcher_badge_class(_), do: "badge-error"

  defp component_description(:watcher), do: "file events, size checks, detection"
  defp component_description(:pipeline), do: "processing steps, batch results"
  defp component_description(:tmdb), do: "API calls, rate limiting, confidence"
  defp component_description(:playback), do: "play/pause/stop, session lifecycle"
  defp component_description(:channel), do: "library sync, entity pushes"
  defp component_description(:library), do: "entity resolver, browser, admin"

  defp framework_label(:ecto), do: "Ecto SQL queries"
  defp framework_label(:phoenix), do: "Phoenix requests"
  defp framework_label(:live_view), do: "LiveView events"

  defp framework_description(:ecto), do: "full SQL dumped on every query"
  defp framework_description(:phoenix), do: "HTTP request logs for every interaction"
  defp framework_description(:live_view), do: "mount, handle_event, handle_params logs"

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
