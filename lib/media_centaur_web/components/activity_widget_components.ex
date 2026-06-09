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
  import MediaCentaurWeb.LibraryOverviewComponents
  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]

  alias MediaCentaur.Library.Availability
  alias MediaCentaur.Status.LibraryOverview
  alias MediaCentaurWeb.Live.SettingsLive.SystemSection

  @doc false
  # Wraps a status-page reference to a configured value so it deep-links to the
  # Settings section that owns it (e.g. the update-automation row → ?section=updates).
  # Keeps the wrapped content's own colour; adds a muted cog that brightens to
  # primary on hover, signalling "this jumps to Settings".
  attr :section, :string,
    required: true,
    doc: ~s|Settings section id, e.g. "updates", "library", "tmdb"|

  attr :class, :any, default: nil, doc: "extra classes for the link wrapper"
  slot :inner_block, required: true

  defp settings_link(assigns) do
    ~H"""
    <.link
      navigate={~p"/settings?section=#{@section}"}
      class={["group/setting inline-flex items-center hover:text-primary transition-colors", @class]}
    >
      {render_slot(@inner_block)}
      <.icon
        name="hero-cog-6-tooth-mini"
        class="size-3 ml-1 shrink-0 text-base-content/30 group-hover/setting:text-primary transition-colors"
      />
    </.link>
    """
  end

  @doc """
  Library subsystem Activity widget: the "Your library" overview — counts,
  size and recently-added (glance), pending review + in-flight acquisitions,
  completeness gaps, and storage outlook. Composes the library-overview cards
  from the `LibraryOverview` view-model the bundle carries.
  """
  attr :overview, LibraryOverview,
    default: nil,
    doc: "Status.fetch_overview/0 result, or nil while the async load is in flight"

  attr :storage_drives, :list,
    required: true,
    doc: "Storage.measure_all/0 drive maps for the storage-outlook card"

  attr :at_risk_summary, :map,
    required: true,
    doc: "AbsenceSweeper.at_risk_summary/0 result, summarized for the storage card"

  attr :ttl_days, :integer, required: true

  def library_widget(assigns) do
    at_risk =
      summarize_at_risk(
        assigns.at_risk_summary,
        Availability.dir_status(),
        DateTime.utc_now(),
        assigns.ttl_days
      )

    assigns = Map.put(assigns, :at_risk, at_risk)

    ~H"""
    <div :if={@overview} class="space-y-3" data-testid="library-widget">
      <.glance_card overview={@overview} />
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-3">
        <.pending_work_card overview={@overview} />
        <.completeness_card overview={@overview} />
        <.storage_outlook_card drives={@storage_drives} at_risk={@at_risk} />
      </div>
    </div>
    <p :if={!@overview} class="text-sm text-base-content/40">Loading library overview…</p>
    """
  end

  @doc "Watcher subsystem Activity widget: watch directories + per-drive storage headroom + at-risk state."
  attr :dir_health, :list,
    required: true,
    doc: "per-watch-dir health maps from Watcher dir-health check (dir/dir_exists/image_dir_exists)"

  attr :watcher_statuses, :list,
    required: true,
    doc:
      "Watcher.Supervisor.statuses/0 entries (dir/state/reason/settling_count/pending_deletions) used to resolve each dir's running state and in-flight activity"

  attr :scan_stats, :map,
    required: true,
    doc:
      "Watcher.Supervisor.scan_stats/0 result — %{dir => %{at, total, new, relinked}} for the last-scan narrative line"

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
        <h2 class="card-title text-lg">
          <.settings_link section="library">Directories</.settings_link>
        </h2>

        <p :if={@dir_health == []} class="text-base-content/60">
          <.settings_link section="library">
            No watch directories configured — add one in Settings.
          </.settings_link>
        </p>

        <div :if={@dir_health != []} class="space-y-4">
          <div :for={health <- @dir_health}>
            <% status = resolve_dir_status(health, @watcher_statuses) %>
            <% watcher = Enum.find(@watcher_statuses, &(&1.dir == health.dir)) %>
            <% last_scan = Map.get(@scan_stats, health.dir) %>
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
              :if={status == :watching && last_scan}
              class="mt-1 text-xs text-base-content/50"
              data-component="last-scan-row"
            >
              Last scan {time_ago(last_scan.at)} · {format_scan_counts(last_scan)}
            </div>

            <div
              :if={watcher && watcher.settling_count > 0}
              class="mt-1 flex items-center gap-1.5 text-xs text-base-content/60"
              data-component="settling-row"
            >
              <.icon name="hero-arrow-path-mini" class="size-3.5 shrink-0" />
              <span>
                {watcher.settling_count} {if watcher.settling_count == 1, do: "file", else: "files"} settling
              </span>
            </div>

            <div
              :if={status == :unavailable}
              class={["mt-1 text-xs", dir_status_text_class(status)]}
              data-component="failure-reason-row"
            >
              {dir_failure_reason_label(watcher && watcher.reason)}
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

  attr :metadata_stats, :map,
    required: true,
    doc:
      "TMDB.MetadataStats.snapshot/0 — %{last_enriched_at, total, recent} for the enrichment-activity feed"

  attr :low_confidence_count, :integer,
    default: nil,
    doc:
      "pending-review (low-confidence) match count, or nil while the library overview is still loading"

  def tmdb_widget(assigns) do
    ~H"""
    <div class="card glass-surface" data-testid="tmdb-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">External Integrations</h2>

        <div class="space-y-3">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-2">
              <span class="text-sm font-medium">TMDB</span>
              <.settings_link
                :if={@config[:tmdb_configured]}
                section="tmdb"
                class="text-success text-xs"
              >
                configured
              </.settings_link>
              <.settings_link
                :if={!@config[:tmdb_configured]}
                section="tmdb"
                class="text-error text-xs"
              >
                not configured
              </.settings_link>
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

        <div class="mt-4 pt-4 border-t border-base-content/10" data-component="metadata-activity">
          <h3 class="text-xs text-base-content/50 uppercase tracking-wide mb-2">Metadata</h3>

          <p :if={@metadata_stats.last_enriched_at} class="text-xs text-base-content/50">
            Last enriched {time_ago(@metadata_stats.last_enriched_at)} · {@metadata_stats.total} this session
          </p>
          <p :if={!@metadata_stats.last_enriched_at} class="text-xs text-base-content/40">
            No metadata fetched yet this session.
          </p>

          <ul :if={@metadata_stats.recent != []} class="mt-2 space-y-0.5">
            <li
              :for={entry <- @metadata_stats.recent}
              id={enriched_row_id(entry)}
              class="flex items-baseline gap-2 text-xs"
            >
              <span class="text-base-content/40 w-16 shrink-0">
                {metadata_kind_label(entry.kind)}
              </span>
              <span class="truncate text-base-content/70">{format_enriched_title(entry)}</span>
              <span class="ml-auto text-base-content/40 shrink-0">{time_ago(entry.at)}</span>
            </li>
          </ul>

          <.link
            :if={@low_confidence_count && @low_confidence_count > 0}
            navigate={~p"/review"}
            class="mt-2 inline-flex items-center gap-1.5 text-xs text-warning hover:text-warning/80"
            data-component="low-confidence-link"
          >
            <.icon name="hero-question-mark-circle-mini" class="size-3.5 shrink-0" />
            {@low_confidence_count} low-confidence {if @low_confidence_count == 1,
              do: "match",
              else: "matches"} to review
          </.link>
        </div>
      </div>
    </div>
    """
  end

  # Stable iterator id (ADR-012) for a recent-enrichment row. Enrichments are
  # seconds apart, so the microsecond stamp is collision-proof in practice.
  defp enriched_row_id(%{at: %DateTime{} = at}), do: "enriched-#{DateTime.to_unix(at, :microsecond)}"

  @doc "Playback subsystem Activity widget: active sessions with now-playing + progress."
  attr :playback, :map,
    required: true,
    doc: "playback view (%{state, now_playing, sessions}) derived by StatusHelpers.derive_playback/1"

  attr :playback_activity, :map,
    required: true,
    doc:
      "watch-activity snapshot from WatchHistory.Views.PlaybackActivity (%{recent, last_write_at, lifetime})"

  def playback_widget(assigns) do
    sessions =
      assigns.playback.sessions
      |> Enum.map(fn {_id, session} -> session end)
      |> Enum.sort_by(fn session -> session[:started_at] || 0 end)

    assigns = Map.put(assigns, :sessions, sessions)

    ~H"""
    <div
      class={["card glass-surface border-l-3", playback_border_class(@playback.state)]}
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

        <%!-- Band 1 · Now / Recently --%>
        <div data-component="playback-narrative" class="mt-1">
          <%!-- playing: one block per active session (unchanged) --%>
          <div :for={session <- @sessions} class="mt-2">
            <div class="flex items-center gap-2">
              <span class={["text-xs", playback_text_class(session.state)]}>{session.state}</span>
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

          <%!-- idle: last-watched line + recent feed --%>
          <div :if={@sessions == [] and @playback_activity.recent != []}>
            <p class="text-sm text-base-content/70">
              Last watched {format_recent_title(hd(@playback_activity.recent))} · {time_ago(
                hd(@playback_activity.recent).at
              )}
            </p>
            <ul class="mt-2 space-y-0.5">
              <li
                :for={entry <- @playback_activity.recent}
                id={watch_row_id(entry)}
                class="flex items-baseline gap-2 text-xs"
              >
                <span class="text-base-content/40 w-16 shrink-0">{watch_kind_label(entry.kind)}</span>
                <span class="truncate text-base-content/70">{format_recent_title(entry)}</span>
                <span class="ml-auto text-base-content/40 shrink-0">{time_ago(entry.at)}</span>
              </li>
            </ul>
          </div>

          <p
            :if={@sessions == [] and @playback_activity.recent == []}
            class="mt-1 text-sm text-base-content/60"
          >
            Nothing watched yet.
          </p>
        </div>

        <%!-- Band 2 · Plumbing health (only band that carries state color) --%>
        <div
          data-component="playback-health"
          class="mt-4 pt-3 border-t border-base-content/10 flex items-center gap-2 text-xs"
        >
          <% health = playback_link_health(@playback.state, @playback_activity.last_write_at) %>
          <span class={["size-2 rounded-full shrink-0", health.dot_class]}></span>
          <span class={health.text_class}>{health.label}</span>
        </div>

        <%!-- Band 3 · Lifetime stats (neutral) --%>
        <div data-component="playback-lifetime" class="mt-3 text-xs text-base-content/50">
          {@playback_activity.lifetime.hours} {pluralize(@playback_activity.lifetime.hours, "hour")} watched
          · {@playback_activity.lifetime.titles} {pluralize(
            @playback_activity.lifetime.titles,
            "title"
          )} completed
          <span :if={@playback_activity.lifetime.streak > 0}>
            · {@playback_activity.lifetime.streak}-day streak
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc "Self-update Activity widget: running version, check cadence, auto-install state, and live apply progress."
  attr :version, :string, required: true, doc: "running app version, e.g. \"0.80.0\""

  attr :status, :any,
    required: true,
    doc: "classification | :checking | :idle | {:error, reason} from SelfUpdate.last_known_status/0"

  attr :latest_release, :map,
    default: nil,
    doc: "last-known release map (tag/published_at/html_url/...) or nil"

  attr :last_check_at, :any,
    required: true,
    doc: "{:ok, DateTime.t()} | :none — timestamp of the last successful check"

  attr :now, DateTime, required: true, doc: "current time, for relative labels"
  attr :check_enabled?, :boolean, required: true, doc: "are background update checks enabled?"
  attr :interval_minutes, :integer, required: true, doc: "configured check interval in minutes"
  attr :auto_install?, :boolean, required: true, doc: "is automatic installation enabled?"

  attr :apply_phase, :atom,
    default: nil,
    doc: "current Updater apply phase, or nil when no apply is in flight"

  attr :apply_progress, :integer, default: nil, doc: "apply progress percent (0-100), or nil"

  attr :history, :list,
    default: [],
    doc: "upgrade history, newest-first: [%{version, recorded_at}] — version + date only"

  def self_update_widget(assigns) do
    ~H"""
    <div class="card glass-surface" data-testid="self-update-widget">
      <div class="card-body">
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Updates</h2>
          <span class="text-sm font-mono text-base-content/60">v{@version}</span>
        </div>

        <p class={["text-sm", SystemSection.tone_class(SystemSection.update_status_tone(@status))]}>
          {SystemSection.update_status_label(@status, @latest_release)}
        </p>

        <div class="text-xs text-base-content/50 space-y-0.5">
          <p>{SystemSection.last_checked_label(@last_check_at, @now)}</p>
          <p>
            <.settings_link section="updates">
              {SystemSection.update_schedule_label(
                @check_enabled?,
                @interval_minutes,
                @last_check_at,
                @now
              )}
            </.settings_link>
          </p>
        </div>

        <.settings_link section="updates" class="gap-2 text-xs">
          <span class="text-base-content/50">Automatic install</span>
          <span class={if @auto_install?, do: "text-success", else: "text-base-content/40"}>
            {if @auto_install?, do: "on", else: "off"}
          </span>
        </.settings_link>

        <div
          :if={@history != []}
          class="mt-1 border-t border-base-content/10 pt-2"
          data-component="update-history"
        >
          <h3 class="text-xs text-base-content/50 mb-1">History</h3>
          <ul class="space-y-0.5">
            <li
              :for={entry <- @history}
              id={history_row_id(entry)}
              class="flex items-center justify-between text-xs"
            >
              <span class="font-mono text-base-content/70">v{entry.version}</span>
              <span class="text-base-content/40">{history_date(entry.recorded_at)}</span>
            </li>
          </ul>
        </div>

        <div :if={apply_active?(@apply_phase)} class="mt-1 space-y-1" data-component="apply-progress">
          <div class="flex items-center justify-between text-xs">
            <span class="text-base-content/70">{SystemSection.apply_phase_label(@apply_phase)}</span>
            <span :if={@apply_progress} class="font-mono text-base-content/50">
              {@apply_progress}%
            </span>
          </div>
          <div class="h-[3px] bg-base-content/10 rounded-full overflow-hidden">
            <div
              class="progress-fill h-full bg-primary rounded-full"
              style={"width: #{@apply_progress || 0}%"}
            >
            </div>
          </div>
        </div>

        <p :if={@apply_phase == :failed} class="mt-1 text-xs text-error" data-component="apply-failed">
          {SystemSection.apply_phase_label(:failed)} — see <.settings_link section="updates">Settings → Updates</.settings_link>.
        </p>
      </div>
    </div>
    """
  end

  # The phases where an apply is genuinely in flight (a progress bar makes sense).
  defp apply_active?(phase),
    do: phase in [:preparing, :downloading, :verifying, :extracting, :handing_off]

  # Friendly, non-zero-padded date for the upgrade-history rows, e.g. "Jun 7, 2026".
  defp history_date(%DateTime{} = at), do: Calendar.strftime(at, "%b %-d, %Y")

  # Stable, unique iterator id (ADR-012). `recorded_at` makes it collision-proof
  # even if the same version appears twice (a deliberate downgrade-then-re-upgrade
  # records two rows, since dedup only compares against the newest entry).
  defp history_row_id(%{version: version, recorded_at: at}),
    do: "update-history-#{version}-#{DateTime.to_unix(at, :microsecond)}"

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

  # Band 2: honest, state-aware plumbing health. The mpv link is per-session, so
  # at rest we report the recorder's proof-of-life (last write), not a fake link.
  defp playback_link_health(state, _last_write_at) when state in [:playing, :paused] do
    %{label: "Link connected", dot_class: "bg-success", text_class: "text-success"}
  end

  defp playback_link_health(:starting, _last_write_at) do
    %{label: "Connecting…", dot_class: "bg-warning", text_class: "text-warning"}
  end

  defp playback_link_health(_idle, nil) do
    %{
      label: "Recorder ready · no writes yet",
      dot_class: "bg-base-content/30",
      text_class: "text-base-content/50"
    }
  end

  defp playback_link_health(_idle, last_write_at) do
    %{
      label: "Recorder ready · last write #{time_ago(last_write_at)}",
      dot_class: "bg-success/60",
      text_class: "text-base-content/50"
    }
  end

  defp watch_kind_label(:movie), do: "Movie"
  defp watch_kind_label(:episode), do: "Episode"
  defp watch_kind_label(:video_object), do: "Video"
  defp watch_kind_label(_), do: "Watch"

  defp format_recent_title(%{title: title}) when is_binary(title) and title != "", do: title
  defp format_recent_title(_), do: "Untitled"

  defp pluralize(1, word), do: word
  defp pluralize(_n, word), do: word <> "s"

  # Stable iterator id (ADR-012): completion timestamps are seconds apart.
  defp watch_row_id(%{at: %DateTime{} = at}), do: "watch-#{DateTime.to_unix(at, :microsecond)}"
end
