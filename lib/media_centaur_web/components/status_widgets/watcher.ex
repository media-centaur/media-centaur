defmodule MediaCentaurWeb.Components.StatusWidgets.Watcher do
  @moduledoc """
  Watcher subsystem Activity widget: media dirs + storage headroom + at-risk state.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers
  import MediaCentaurWeb.LiveHelpers, only: [time_ago: 1]
  import MediaCentaurWeb.Components.StatusWidgets.Shared

  alias MediaCentaur.Library.Availability

  @doc "Watcher subsystem Activity widget: media directories + per-drive storage headroom + at-risk state."
  attr :dir_health, :list,
    required: true,
    doc: "per-media-dir health maps from Watcher dir-health check (dir/dir_exists/image_dir_exists)"

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
    <div class="card glass-inset" data-testid="watcher-widget">
      <div class="card-body">
        <h2 class="card-title text-lg">
          <.settings_link section="library">Directories</.settings_link>
        </h2>

        <p :if={@dir_health == []} class="text-base-content/60">
          <.settings_link section="library">
            No media directories configured — add one in Settings.
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
                class={["progress h-1.5 flex-1", storage_progress_class(storage_severity(drive))]}
                value={drive.usage_percent}
                max="100"
              >
              </progress>
              <span class={[
                "text-xs font-mono w-10 text-right shrink-0",
                storage_text_class(storage_severity(drive))
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
              class={["progress h-1.5 flex-1", storage_progress_class(storage_severity(@db_drive))]}
              value={@db_drive.usage_percent}
              max="100"
            >
            </progress>
            <span class={[
              "text-xs font-mono w-10 text-right",
              storage_text_class(storage_severity(@db_drive))
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
