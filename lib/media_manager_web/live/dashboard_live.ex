defmodule MediaManagerWeb.DashboardLive do
  use MediaManagerWeb, :live_view

  alias MediaManager.Dashboard

  @impl true
  def mount(_params, _session, socket) do
    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "watcher:state")
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "library:updates")
        Phoenix.PubSub.subscribe(MediaManager.PubSub, "playback:events")

        stats = Dashboard.fetch_stats()

        socket
        |> assign(watcher_statuses: MediaManager.Watcher.Supervisor.statuses())
        |> assign(library_stats: stats.library)
        |> assign(pipeline_stats: stats.pipeline)
        |> assign(pending_review: stats.pending_review)
        |> assign(recent_errors: stats.recent_errors)
        |> assign(playback: MediaManager.Playback.Manager.current_state())
        |> assign(config: load_config())
      else
        socket
        |> assign(watcher_statuses: [])
        |> assign(library_stats: %{entities: 0, files: 0, images: 0, by_type: %{}})
        |> assign(pipeline_stats: %{})
        |> assign(pending_review: [])
        |> assign(recent_errors: [])
        |> assign(playback: %{state: :idle, now_playing: nil})
        |> assign(config: %{})
      end

    {:ok, assign(socket, scanning: false)}
  end

  @impl true
  def handle_event("scan", _params, socket) do
    socket = assign(socket, scanning: true)

    case MediaManager.Watcher.Supervisor.scan() do
      {:ok, count} ->
        message =
          case count do
            0 -> "Scan complete — no new files found"
            1 -> "Scan complete — 1 new file detected"
            n -> "Scan complete — #{n} new files detected"
          end

        {:noreply, socket |> put_flash(:info, message) |> assign(scanning: false)}
    end
  end

  @impl true
  def handle_info({:watcher_state_changed, _dir, _new_state}, socket) do
    {:noreply, assign(socket, watcher_statuses: MediaManager.Watcher.Supervisor.statuses())}
  end

  def handle_info({:entities_changed, _entity_ids}, socket) do
    stats = Dashboard.fetch_stats()

    {:noreply,
     socket
     |> assign(library_stats: stats.library)
     |> assign(pipeline_stats: stats.pipeline)
     |> assign(pending_review: stats.pending_review)
     |> assign(recent_errors: stats.recent_errors)}
  end

  def handle_info({:playback_state_changed, _new_state, _now_playing}, socket) do
    {:noreply, assign(socket, playback: MediaManager.Playback.Manager.current_state())}
  end

  def handle_info({:playback_progress, _progress}, socket) do
    {:noreply, assign(socket, playback: MediaManager.Playback.Manager.current_state())}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
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

        <.library_stats stats={@library_stats} />
        <.pipeline_status stats={@pipeline_stats} />
        <.watcher_health statuses={@watcher_statuses} />
        <.playback_status playback={@playback} />
        <.pending_review_table files={@pending_review} />
        <.recent_errors_table files={@recent_errors} />
        <.config_overview config={@config} />
      </div>
    </Layouts.app>
    """
  end

  # --- Section Components ---

  defp library_stats(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Library Stats</h2>

        <div class="stats stats-horizontal bg-base-200 w-full">
          <div class="stat">
            <div class="stat-title">Total Entities</div>
            <div class="stat-value text-2xl">{@stats.entities}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Total Files</div>
            <div class="stat-value text-2xl">{@stats.files}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Total Images</div>
            <div class="stat-value text-2xl">{@stats.images}</div>
          </div>
        </div>

        <div class="stats stats-horizontal bg-base-200 w-full">
          <div :for={{type, count} <- Enum.sort(@stats.by_type)} class="stat">
            <div class="stat-title">{format_type(type)}</div>
            <div class="stat-value text-2xl">{count}</div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp pipeline_status(assigns) do
    ~H"""
    <div class="card bg-base-100 shadow-sm">
      <div class="card-body">
        <h2 class="card-title text-lg">Pipeline Status</h2>

        <div class="flex flex-wrap items-center gap-2">
          <span
            :for={stage <- pipeline_stages()}
            class="flex items-center gap-2"
          >
            <span class={["badge gap-1", pipeline_badge_class(stage.key, @stats[stage.key] || 0)]}>
              {@stats[stage.key] || 0}
              <span>{stage.label}</span>
            </span>
            <.icon :if={stage.arrow} name="hero-arrow-right-micro" class="size-3 opacity-40" />
          </span>
        </div>

        <div :if={has_side_states?(@stats)} class="divider my-1" />

        <div :if={has_side_states?(@stats)} class="flex flex-wrap gap-2">
          <span
            :for={stage <- side_stages()}
            class={["badge gap-1", pipeline_badge_class(stage.key, @stats[stage.key] || 0)]}
          >
            {@stats[stage.key] || 0}
            <span>{stage.label}</span>
          </span>
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
        <h2 class="card-title text-lg">
          Pending Review
          <span :if={@files != []} class="badge badge-warning badge-sm">{length(@files)}</span>
        </h2>

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
                    :if={file.confidence_score}
                    class={["badge badge-sm", confidence_badge_class(file.confidence_score)]}
                  >
                    {Float.round(file.confidence_score, 2)}
                  </span>
                  <span :if={!file.confidence_score} class="text-base-content/40">—</span>
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
                <th>File</th>
                <th>Error Message</th>
                <th>Updated At</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={file <- @files}>
                <td class="font-mono text-xs max-w-xs truncate">{Path.basename(file.file_path)}</td>
                <td class="text-error text-xs max-w-md truncate">{file.error_message || "—"}</td>
                <td class="text-xs">{format_datetime(file.updated_at)}</td>
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
            <span class="text-base-content/60">TMDB API Key</span>
            <span :if={@config[:tmdb_configured]} class="badge badge-success badge-sm">
              configured
            </span>
            <span :if={!@config[:tmdb_configured]} class="badge badge-error badge-sm">
              not configured
            </span>
          </div>
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

  # --- Helpers ---

  defp format_type(:movie), do: "Movies"
  defp format_type(:movie_series), do: "Movie Series"
  defp format_type(:tv_series), do: "TV Series"
  defp format_type(:video_object), do: "Videos"
  defp format_type(type), do: type |> to_string() |> String.capitalize()

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
    config = MediaManager.Config

    %{
      tmdb_configured: config.get(:tmdb_api_key) not in [nil, ""],
      auto_approve_threshold: config.get(:auto_approve_threshold),
      mpv_path: config.get(:mpv_path),
      media_images_dir: config.get(:media_images_dir),
      database_path: config.get(:database_path),
      watch_dirs_count: length(config.get(:watch_dirs) || [])
    }
  end

  defp pipeline_stages do
    [
      %{key: :detected, label: "detected", arrow: true},
      %{key: :queued, label: "queued", arrow: true},
      %{key: :searching, label: "searching", arrow: true},
      %{key: :approved, label: "approved", arrow: true},
      %{key: :fetching_metadata, label: "fetching metadata", arrow: true},
      %{key: :fetching_images, label: "fetching images", arrow: true},
      %{key: :complete, label: "complete", arrow: false}
    ]
  end

  defp side_stages do
    [
      %{key: :pending_review, label: "pending review"},
      %{key: :error, label: "error"},
      %{key: :removed, label: "removed"}
    ]
  end

  defp has_side_states?(stats) do
    Enum.any?([:pending_review, :error, :removed], fn key ->
      (stats[key] || 0) > 0
    end)
  end

  defp pipeline_badge_class(_key, 0), do: "badge-ghost"
  defp pipeline_badge_class(:complete, _), do: "badge-success"
  defp pipeline_badge_class(:error, _), do: "badge-error"
  defp pipeline_badge_class(:pending_review, _), do: "badge-warning"
  defp pipeline_badge_class(:removed, _), do: "badge-ghost"
  defp pipeline_badge_class(_, _), do: "badge-info"

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
