defmodule MediaCentaurWeb.HealthComponents do
  @moduledoc """
  Function components for the Subsystem Health Board (Phase 4). Identity is
  name + a neutral monochrome glyph + type; color is reserved exclusively for
  health/severity (see the Phase 4 design spec, D7). Presentation only — the
  view-model logic lives in `MediaCentaurWeb.StatusLive.HealthBoard`.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.RetentionPanel, only: [retention_panel: 1]

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

  @doc """
  One incident row in the drill-in Issues section. The row body is a button that
  opens the issue view (`on_select`); the X dismisses (`on_dismiss`). Reporting
  is no longer on the row — it lives inside the issue view, so it follows reading
  the incident rather than preceding it.
  """
  attr :bucket, Bucket, required: true
  attr :on_select, :string, default: "select_incident"
  attr :on_dismiss, :string, default: "dismiss_incident"

  def incident_row(assigns) do
    ~H"""
    <div id={"incident-#{@bucket.fingerprint}"} class="glass-inset rounded-lg flex items-stretch">
      <button
        type="button"
        phx-click={@on_select}
        phx-value-fingerprint={@bucket.fingerprint}
        data-nav-item
        class="flex-1 min-w-0 flex items-start gap-3 p-3 text-left rounded-l-lg cursor-pointer hover:bg-base-content/5 transition-colors"
      >
        <span class={[
          "size-2 rounded-full shrink-0 mt-1.5",
          @bucket.severity == :warning && "bg-warning",
          @bucket.severity in [:error, :critical] && "bg-error"
        ]} />
        <span class="min-w-0 flex-1">
          <span class="block text-sm truncate">{@bucket.display_title}</span>
          <span class="block text-xs text-base-content/50 mt-0.5">
            {@bucket.count}× · since {Calendar.strftime(@bucket.first_seen, "%b %-d, %H:%M")}
          </span>
        </span>
      </button>
      <.button
        variant="dismiss"
        size="xs"
        shape="square"
        aria-label="Dismiss"
        class="m-2 self-center"
        phx-click={@on_dismiss}
        phx-value-fingerprint={@bucket.fingerprint}
      >
        <.icon name="hero-x-mark-mini" class="size-4" />
      </.button>
    </div>
    """
  end

  @doc """
  Inline drill-in for one subsystem, composed as an editorial instrument panel:
  a masthead (kicker → title → lede briefing) over an asymmetric body — the
  wide primary column carries the subsystem's Activity narrative, the quiet
  right rail carries the plumbing (Status → Data retention → collapsed Logs).
  Subsystems without a registered Activity widget (the health-only floor)
  collapse to a single narrow column of rail cards.
  """
  attr :view, SubsystemView, required: true
  attr :buckets, :list, required: true, doc: "[Bucket.t()] for this subsystem"
  attr :retention, :list, default: [], doc: "[Retention.PolicyStatus.t()] for this subsystem"
  attr :on_select, :string, default: "select_incident"
  attr :on_dismiss, :string, default: "dismiss_incident"
  attr :on_dismiss_all, :string, default: "dismiss_all"
  attr :on_close, :string, default: "close_subsystem"
  slot :activity, doc: "the subsystem's bespoke Activity widget"

  def health_drill_in(assigns) do
    ~H"""
    <section id="health-drill-in" class="glass-surface rounded-xl p-6 lg:p-8">
      <header class="mb-8 flex items-start justify-between gap-4 border-b border-base-content/10 pb-7">
        <div class="min-w-0">
          <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.14em] text-base-content/40">
            <.icon name={@view.glyph} class="size-3.5 opacity-70" /> Subsystem
          </div>
          <h2 class="mt-2 text-3xl font-semibold tracking-tight">{@view.label}</h2>
          <p class="mt-3 max-w-prose text-[0.9375rem] leading-relaxed text-base-content/65">
            {HealthBoard.description(@view.component)}
          </p>
        </div>
        <.button variant="dismiss" size="sm" phx-click={@on_close}>Close</.button>
      </header>

      <div class={[
        @activity != [] && "grid items-start gap-8 lg:grid-cols-[minmax(0,1fr)_21rem]",
        @activity == [] && "max-w-xl"
      ]}>
        <%!-- No eyebrow here: the masthead already names the subsystem, and a
             label outside the card would break top-alignment with the rail
             (every section label lives inside its card). --%>
        <div :if={@activity != []} class="min-w-0">
          {render_slot(@activity)}
        </div>

        <aside class="flex min-w-0 flex-col gap-3.5">
          <div class="glass-inset rounded-xl p-5">
            <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/50">
              Status
            </h3>
            <div class="mt-3.5 flex items-center gap-2">
              <span class={["size-2 shrink-0 rounded-full", state_dot_class(@view.state)]}></span>
              <span class={["text-sm font-medium", state_text_class(@view.state)]}>
                {state_label(@view.state)}
              </span>
              <span :if={@view.state != :ok} class="text-xs text-base-content/40">
                {HealthBoard.tile_summary(@view)}
              </span>
            </div>

            <%!-- Composed all-clear: a deliberate confirmation, not floating copy. --%>
            <div
              :if={@buckets == []}
              class="mt-3.5 flex items-start gap-2.5 border-t border-base-content/10 pt-3.5 text-sm text-base-content/50"
            >
              <span class="mt-0.5 grid size-4 shrink-0 place-items-center rounded-full bg-success/15">
                <.icon name="hero-check-mini" class="size-3 text-success" />
              </span>
              <span class="font-medium text-base-content/65">No issues</span>
            </div>

            <div :if={@buckets != []} class="mt-3.5 border-t border-base-content/10 pt-3.5">
              <div class="mb-2 flex items-center justify-between">
                <h4 class="text-xs font-medium uppercase tracking-wider text-base-content/40">
                  Issues
                </h4>
                <.button variant="dismiss" size="xs" phx-click={@on_dismiss_all}>
                  Dismiss all
                </.button>
              </div>
              <div class="space-y-2">
                <.incident_row
                  :for={bucket <- @buckets}
                  bucket={bucket}
                  on_select={@on_select}
                  on_dismiss={@on_dismiss}
                />
              </div>
            </div>
          </div>

          <.retention_panel :if={@retention != []} policies={@retention} />

          <details class="glass-inset rounded-xl">
            <summary class="cursor-pointer select-none px-4 py-3 text-sm text-base-content/60">
              Technical logs
            </summary>
            <div class="space-y-0.5 border-t border-base-content/10 px-4 py-3 font-mono text-xs text-base-content/50">
              <p :for={line <- HealthBoard.log_lines(@buckets)}>{line}</p>
              <p :if={HealthBoard.log_lines(@buckets) == []}>No recent log lines.</p>
            </div>
          </details>
        </aside>
      </div>
    </section>
    """
  end

  # Rail status line: color rides the dot and (when unhealthy) the label —
  # calm-when-healthy keeps the "Healthy" word in neutral ink.
  defp state_dot_class(:ok), do: "bg-success/55"
  defp state_dot_class(:warning), do: "bg-warning"
  defp state_dot_class(:error), do: "bg-error"

  defp state_text_class(:ok), do: "text-base-content/65"
  defp state_text_class(:warning), do: "text-warning"
  defp state_text_class(:error), do: "text-error"

  defp state_label(:ok), do: "Healthy"
  defp state_label(:warning), do: "Warning"
  defp state_label(:error), do: "Error"
end
