defmodule MediaCentaurWeb.Components.StatusWidgets.System do
  @moduledoc """
  System (runtime) Activity widget: uptime, BEAM vitals, host facts, datastore footprint.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.StatusHelpers

  @doc "System (runtime) Activity widget: uptime, BEAM vitals, host facts, datastore footprint."
  attr :system_vitals, :map,
    required: true,
    doc:
      "Runtime.Vitals.snapshot/0 bundle (uptime_seconds, memory, process_*, run_queue, schedulers, host, db)"

  def system_widget(assigns) do
    v = assigns.system_vitals
    proc_tone = if v.process_count > v.process_limit * 0.8, do: :warning, else: :ok
    rq_tone = if v.run_queue > v.schedulers, do: :warning, else: :ok

    assigns =
      assigns
      |> Map.put(:proc_tone, proc_tone)
      |> Map.put(:rq_tone, rq_tone)

    ~H"""
    <div class="card glass-inset" data-testid="system-widget">
      <div class="card-body">
        <%!-- Header + uptime (stability headline) --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">System</h2>
          <span class="text-xs text-base-content/60">
            Up {format_uptime(@system_vitals.uptime_seconds)}
          </span>
        </div>

        <%!-- Vitals stat figures (neutral) --%>
        <div data-component="system-vitals" class="mt-2 grid grid-cols-3 gap-3">
          <div>
            <div class="text-2xl font-semibold tabular-nums">
              {format_bytes_iec(@system_vitals.memory.total)}
            </div>
            <div class="text-xs uppercase tracking-wider text-base-content/55">Memory</div>
          </div>
          <div>
            <div class="text-2xl font-semibold tabular-nums">{@system_vitals.process_count}</div>
            <div class="text-xs uppercase tracking-wider text-base-content/55">Processes</div>
          </div>
          <div>
            <div class="text-2xl font-semibold tabular-nums">
              {format_bytes_iec(@system_vitals.db.size_bytes)}
            </div>
            <div class="text-xs uppercase tracking-wider text-base-content/55">Database</div>
          </div>
        </div>

        <%!-- Runtime detail rows (color = signal) --%>
        <div
          data-component="system-detail"
          class="mt-3 pt-3 border-t border-base-content/10 grid grid-cols-2 gap-x-6 gap-y-1.5 text-xs"
        >
          <div class="flex items-baseline gap-2">
            <span class="text-base-content/55">Schedulers</span>
            <span class="tabular-nums text-base-content/80">{@system_vitals.schedulers}</span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-base-content/55">Run queue</span>
            <span class={["tabular-nums", vital_value_class(@rq_tone)]}>
              {@system_vitals.run_queue}
            </span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-base-content/55">Processes</span>
            <span class={["tabular-nums", vital_value_class(@proc_tone)]}>
              {@system_vitals.process_count} / {@system_vitals.process_limit}
            </span>
          </div>
          <div class="flex items-baseline gap-2">
            <span class="text-base-content/55">WAL</span>
            <span class="tabular-nums text-base-content/80">
              {format_bytes_iec(@system_vitals.db.wal_bytes)}
            </span>
          </div>
        </div>

        <%!-- Host / build footer (quiet) --%>
        <div data-component="system-host" class="mt-3 text-xs text-base-content/55">
          OTP {@system_vitals.host.otp} · Elixir {@system_vitals.host.elixir} · {@system_vitals.host.os}
        </div>
      </div>
    </div>
    """
  end

  # System vitals read calm-when-healthy: neutral by default, amber only when a
  # vital is concerning (color = signal). Distinct from `tone_chrome/1`, whose
  # `:ok` is success-green (right for a "Connected" status, wrong for a fine metric).
  defp vital_value_class(:warning), do: "text-warning"
  defp vital_value_class(_ok), do: "text-base-content/70"

  defp format_uptime(seconds) when seconds < 60, do: "#{seconds}s"
  defp format_uptime(seconds) when seconds < 3600, do: "#{div(seconds, 60)}m"

  defp format_uptime(seconds) when seconds < 86_400,
    do: "#{div(seconds, 3600)}h #{rem(div(seconds, 60), 60)}m"

  defp format_uptime(seconds), do: "#{div(seconds, 86_400)}d #{rem(div(seconds, 3600), 24)}h"
end
