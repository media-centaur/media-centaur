defmodule MediaCentaurWeb.HealthComponents do
  @moduledoc """
  Function components for the Subsystem Health Board (Phase 4). Identity is
  name + a neutral monochrome glyph + type; color is reserved exclusively for
  health/severity (see the Phase 4 design spec, D7). Presentation only — the
  view-model logic lives in `MediaCentaurWeb.StatusLive.HealthBoard`.
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.ErrorReports.Bucket
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
      data-subsystem-tile
      data-selected={@selected}
      aria-pressed={to_string(@selected)}
      tabindex="0"
      class={[
        "glass-surface rounded-xl p-4 text-left w-full flex items-start gap-3 cursor-pointer transition-colors",
        @view.state == :error && "border-l-2 border-error",
        @view.state == :warning && "border-l-2 border-warning"
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
  attr :on_dismiss, :string, default: "dismiss_incident"

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
      <.button
        variant="dismiss"
        size="xs"
        shape="square"
        aria-label="Dismiss"
        phx-click={@on_dismiss}
        phx-value-fingerprint={@bucket.fingerprint}
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </.button>
    </div>
    """
  end

  @doc "Inline stacked drill-in for one subsystem: Issues → Activity → collapsed Logs."
  attr :view, SubsystemView, required: true
  attr :buckets, :list, required: true, doc: "[Bucket.t()] for this subsystem"
  attr :on_report, :string, default: "report_incident"
  attr :on_dismiss, :string, default: "dismiss_incident"
  attr :on_dismiss_all, :string, default: "dismiss_all"
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
        <div class="flex items-center justify-between">
          <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">Issues</h3>
          <.button variant="dismiss" size="xs" phx-click={@on_dismiss_all}>Dismiss all</.button>
        </div>
        <.incident_row
          :for={bucket <- @buckets}
          bucket={bucket}
          on_report={@on_report}
          on_dismiss={@on_dismiss}
        />
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
end
