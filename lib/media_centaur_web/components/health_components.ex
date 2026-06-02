defmodule MediaCentaurWeb.HealthComponents do
  @moduledoc """
  Function components for the Subsystem Health Board (Phase 4). Identity is
  name + a neutral monochrome glyph + type; color is reserved exclusively for
  health/severity (see the Phase 4 design spec, D7). Presentation only — the
  view-model logic lives in `MediaCentaurWeb.StatusLive.HealthBoard`.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaur.Library.Availability
  alias MediaCentaurWeb.StatusLive.HealthBoard
  alias MediaCentaurWeb.StatusLive.SubsystemView

  @doc "One subsystem tile: name + neutral glyph + type; color only for health."
  attr :view, SubsystemView, required: true
  attr :selected, :boolean, default: false
  attr :on_select, :string, default: "select_subsystem"

  def subsystem_tile(assigns) do
    ~H"""
    <button
      id={"subsystem-tile-#{@view.component}"}
      type="button"
      phx-click={@on_select}
      phx-value-subsystem={@view.component}
      data-nav-item
      tabindex="0"
      class={[
        "glass-surface rounded-xl p-4 text-left w-full flex items-start gap-3 transition-colors",
        @view.state == :error && "border-l-2 border-error",
        @view.state == :warning && "border-l-2 border-warning",
        @selected && "ring-1 ring-primary/40"
      ]}
    >
      <.icon name={@view.glyph} class="size-5 shrink-0 text-base-content/65 mt-0.5" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <span class="font-medium truncate">{@view.label}</span>
          <span class={[
            "size-2 rounded-full shrink-0",
            @view.state == :ok && "bg-success/55",
            @view.state == :warning && "bg-warning",
            @view.state == :error && "bg-error"
          ]} />
        </div>
        <p class="text-sm text-base-content/55 mt-1">{HealthBoard.tile_summary(@view)}</p>
      </div>
    </button>
    """
  end

  @doc "One reportable incident row in the drill-in Issues section."
  attr :bucket, Bucket, required: true
  attr :on_report, :string, default: "report_incident"

  def incident_row(assigns) do
    ~H"""
    <div
      id={"incident-#{@bucket.fingerprint}"}
      class="glass-inset rounded-lg p-3 flex items-start gap-3"
    >
      <span class={[
        "size-2 rounded-full shrink-0 mt-1.5",
        @bucket.severity == :warning && "bg-warning",
        @bucket.severity in [:error, :critical] && "bg-error"
      ]} />
      <div class="min-w-0 flex-1">
        <p class="text-sm">{@bucket.display_title}</p>
        <p class="text-xs text-base-content/50 mt-0.5">
          {@bucket.count}× · since {Calendar.strftime(@bucket.first_seen, "%b %-d, %H:%M")}
        </p>
      </div>
      <.button
        variant="neutral"
        size="xs"
        phx-click={@on_report}
        phx-value-fingerprint={@bucket.fingerprint}
      >
        Report this
      </.button>
    </div>
    """
  end

  @doc "Inline stacked drill-in for one subsystem: Issues → Activity → collapsed Logs."
  attr :view, SubsystemView, required: true
  attr :buckets, :list, required: true, doc: "[Bucket.t()] for this subsystem"
  attr :on_report, :string, default: "report_incident"
  attr :on_close, :string, default: "close_subsystem"
  slot :activity, doc: "the subsystem's bespoke Activity widget"

  def health_drill_in(assigns) do
    ~H"""
    <section id="health-drill-in" class="glass-surface rounded-xl p-5 space-y-5">
      <header class="flex items-center justify-between">
        <div class="flex items-center gap-2">
          <.icon name={@view.glyph} class="size-5 text-base-content/65" />
          <h2 class="text-lg font-medium">{@view.label}</h2>
        </div>
        <.button variant="dismiss" size="sm" phx-click={@on_close}>Close</.button>
      </header>

      <div :if={@buckets != []} class="space-y-2">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Issues</h3>
        <.incident_row :for={bucket <- @buckets} bucket={bucket} on_report={@on_report} />
      </div>
      <p :if={@buckets == []} class="text-sm text-base-content/55">No issues for this subsystem.</p>

      <div :if={@activity != []} class="space-y-2">
        <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Activity</h3>
        {render_slot(@activity)}
      </div>

      <details class="glass-inset rounded-lg">
        <summary class="cursor-pointer select-none px-3 py-2 text-sm text-base-content/60">
          View technical logs
        </summary>
        <div class="px-3 pb-3 text-xs font-mono text-base-content/50 space-y-0.5">
          <p :for={line <- HealthBoard.log_lines(@buckets)}>{line}</p>
          <p :if={HealthBoard.log_lines(@buckets) == []}>No recent log lines.</p>
        </div>
      </details>
    </section>
    """
  end

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
end
