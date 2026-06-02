defmodule MediaCentaurWeb.ActivityWidgetComponents do
  @moduledoc """
  Per-subsystem Activity-widget function components rendered into the
  health-board drill-in's `:activity` slot via
  `MediaCentaurWeb.StatusLive.ActivityWidgets`. Each widget is invoked with a
  plain data bundle (no change-tracking) assembled by
  `StatusLive.activity_bundle/1`, so derive values with `Map.put/3`, never
  `assign/3`.

  Lives under `lib/media_centaur_web/`, so it is inside the `MediaCentaurWeb`
  boundary.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers

  alias MediaCentaur.Library.Availability

  @doc "Watcher subsystem Activity widget: watch directories + per-drive storage headroom + at-risk state."
  attr :dir_health, :list,
    required: true,
    doc: "per-watch-dir health maps from Watcher dir-health check (dir/dir_exists/image_dir_exists)"

  attr :watcher_statuses, :list,
    required: true,
    doc: "Watcher.Supervisor.statuses/0 entries used to resolve each dir's running state"

  attr :storage_drives, :list,
    required: true,
    doc: "Storage.measure_all/0 drive maps (roles/used_bytes/total_bytes/usage_percent)"

  attr :at_risk_summary, :map,
    required: true,
    doc: "AbsenceSweeper.at_risk_summary/0 result keyed by dir, for TTL-purge warnings"

  attr :ttl_days, :integer, required: true

  def watcher_widget(assigns) do
    db_drive =
      Enum.find(assigns.storage_drives, fn drive ->
        Enum.any?(drive.roles, &(&1.label == "Database"))
      end)

    assigns =
      assigns
      |> Map.put(:db_drive, db_drive)
      |> Map.put(:dir_status, Availability.dir_status())
      |> Map.put(:now, DateTime.utc_now())

    ~H"""
    <div class="card glass-surface" data-testid="watcher-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">Directories</h2>

        <p :if={@dir_health == []} class="text-base-content/60">
          No watch directories configured.
        </p>

        <div :if={@dir_health != []} class="space-y-4">
          <div :for={health <- @dir_health}>
            <% status = resolve_dir_status(health, @watcher_statuses) %>
            <% drive = find_drive_for_dir(@storage_drives, health.dir) %>
            <% at_risk =
              format_at_risk_for_dir(
                health.dir,
                @at_risk_summary,
                @dir_status,
                @now,
                @ttl_days
              ) %>

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

            <div
              :if={at_risk}
              class="mt-2 flex items-center gap-2 text-xs text-warning"
              data-component="at-risk-row"
            >
              <.icon name="hero-exclamation-triangle-mini" class="size-4 shrink-0" />
              <span>
                {at_risk.file_count} {if at_risk.file_count == 1, do: "file", else: "files"} at risk of TTL purge
                <span :if={at_risk.purge_in_days > 0}>
                  in {at_risk.purge_in_days} {if at_risk.purge_in_days == 1, do: "day", else: "days"}
                </span>
                <span :if={at_risk.purge_in_days == 0} class="text-error font-medium">
                  — purge eligible now (waiting for drive to come back online)
                </span>
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

  defp find_drive_for_dir(drives, dir) do
    Enum.find(drives, fn drive ->
      Enum.any?(drive.roles, &(&1.path == dir))
    end)
  end

  @stage_grid_columns "grid-template-columns: 0.5rem 1fr 5rem 4.5rem 4.5rem 3rem"

  @doc "Pipeline subsystem Activity widget: content + image pipeline stages with throughput/latency/slots."
  attr :content_stats, :map,
    required: true,
    doc: "Pipeline.Stats snapshot (queue_depth/total_failed/stages keyed by stage atom)"

  attr :image_stats, :map,
    required: true,
    doc: "Pipeline.Image.Stats snapshot (status/throughput/avg_duration_ms/active_count/totals)"

  attr :retry_status, :map,
    default: nil,
    doc: "%{retrying_count: integer} from the image queue, or nil when unavailable"

  attr :pipeline_concurrency, :integer, required: true
  attr :image_concurrency, :integer, required: true

  def pipeline_widget(assigns) do
    assigns =
      assigns
      |> Map.put(:stage_order, [:parse, :search, :fetch_metadata, :ingest])
      |> Map.put(:grid_columns, @stage_grid_columns)

    ~H"""
    <div class="card glass-surface self-start" data-testid="pipeline-widget">
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

  attr :stage, :atom, required: true
  attr :data, :map, required: true, doc: "per-stage snapshot map (status/throughput/avg/active_count)"
  attr :concurrency, :integer, required: true
  attr :grid_columns, :string, required: true

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

  @doc "TMDB subsystem Activity widget: external-integration configuration + rate-limiter budget."
  attr :rate_limiter, :map,
    default: nil,
    doc: "TMDB.RateLimiter.status/0 result (%{used, total}), or nil when not started"

  attr :config, :map,
    required: true,
    doc: "status-page config map (tmdb_configured? + related runtime config keys)"

  def tmdb_widget(assigns) do
    ~H"""
    <div class="card glass-surface" data-testid="tmdb-widget">
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

  @doc "Playback subsystem Activity widget: active sessions with now-playing + progress."
  attr :playback, :map,
    required: true,
    doc: "playback view (%{state, now_playing, sessions}) derived by StatusHelpers.derive_playback/1"

  def playback_widget(assigns) do
    sessions =
      assigns.playback.sessions
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(fn session -> session[:started_at] || 0 end)

    assigns = Map.put(assigns, :sessions, sessions)

    ~H"""
    <div
      class={[
        "card glass-surface border-l-3",
        playback_border_class(@playback.state)
      ]}
      data-testid="playback-widget"
    >
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
