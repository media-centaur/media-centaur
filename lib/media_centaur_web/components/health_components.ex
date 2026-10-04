defmodule MediaCentaurWeb.HealthComponents do
  @moduledoc """
  Function components for the Subsystem Health Board (Phase 4). Identity is
  name + a neutral monochrome glyph + type; color is reserved exclusively for
  health/severity (see the Phase 4 design spec, D7). Presentation only — the
  view-model logic lives in `MediaCentaurWeb.StatusLive.HealthBoard`.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.RetentionPanel, only: [retention_panel: 1]
  import MediaCentaurWeb.ConsoleComponents, only: [log_line: 1, log_view: 1]

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.Live.DisclosureState
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
      data-entity-id={@view.component}
      data-subsystem-tile
      data-selected={@selected}
      aria-pressed={to_string(@selected)}
      tabindex="0"
      class={[
        "glass-surface rounded-xl p-4 text-left w-full flex items-start gap-3 cursor-pointer transition-colors",
        @view.state == :error && "bg-error/5",
        @view.state == :warning && "bg-warning/5"
      ]}
    >
      <.icon name={@view.glyph} class="size-5 shrink-0 text-base-content/65 mt-0.5" />
      <div class="min-w-0 flex-1">
        <div class="flex items-center gap-2">
          <span class="font-medium truncate">{@view.label}</span>
          <span class={[
            "size-2 rounded-full shrink-0",
            @view.state == :dormant && "bg-base-content/25",
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
        tabindex="0"
        class="flex-1 min-w-0 flex items-start gap-3 p-3 text-left rounded-l-lg cursor-pointer hover:bg-base-content/5 transition-colors"
      >
        <span class={[
          "size-2 rounded-full shrink-0 mt-1.5",
          @bucket.severity == :warning && "bg-warning",
          @bucket.severity in [:error, :critical] && "bg-error"
        ]} />
        <span class="min-w-0 flex-1">
          <span class="block text-sm truncate">{@bucket.headline}</span>
          <span class="block text-xs text-base-content/55 mt-0.5">
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
        data-nav-item
        tabindex="0"
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
  right rail carries the plumbing (Status → Data retention). Subsystems
  without a registered Activity widget (the health-only floor) collapse to a
  single narrow column of rail cards.

  The logs sit beneath the body at the drill-in's full width: a log line is
  read and scanned, and the rail's 21rem wrapped every line several times.
  The subsystem's own lines are a preview — the latest few, oldest first —
  with a link to the console scoped to the subsystem, which is where logs are
  read, followed, filtered and searched. The System journal, which has no
  console counterpart, is a `log_view/1` that follows its live edge.
  """
  attr :view, SubsystemView, required: true
  attr :buckets, :list, required: true, doc: "[Bucket.t()] for this subsystem"
  attr :retention, :list, default: [], doc: "[Retention.PolicyStatus.t()] for this subsystem"

  attr :log_lines, :list,
    default: [],
    doc: "[Console.Entry.t()] the latest lines for this subsystem, oldest first"

  attr :show_log_components, :boolean,
    default: false,
    doc: "per-line component badges; true only where a subsystem folds more than one tag"

  attr :disclosures, :any,
    default: MapSet.new(),
    doc: "the page's `DisclosureState` — which disclosures the user toggled."

  attr :on_select, :string, default: "select_incident"
  attr :on_dismiss, :string, default: "dismiss_incident"
  attr :on_dismiss_all, :string, default: "dismiss_all"
  attr :on_close, :string, default: "close_subsystem"
  slot :activity, doc: "the subsystem's bespoke Activity widget"

  slot :logs,
    doc: "extra log panels for this subsystem, after the technical logs (the System journal)"

  def health_drill_in(assigns) do
    ~H"""
    <section
      id="health-drill-in"
      data-nav-zone="drill-in"
      class="@container glass-surface rounded-xl p-6 @4xl:p-8"
    >
      <header class="mb-8 flex items-start justify-between gap-4 border-b border-base-content/10 pb-7">
        <div class="min-w-0">
          <div class="flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.14em] text-base-content/55">
            <.icon name={@view.glyph} class="size-3.5 opacity-70" /> Subsystem
          </div>
          <h2 class="mt-2 text-3xl font-semibold tracking-tight">{@view.label}</h2>
          <p class="mt-3 max-w-prose text-[0.9375rem] leading-relaxed text-base-content/65">
            {HealthBoard.description(@view.component)}
          </p>
        </div>
        <.button variant="dismiss" size="sm" phx-click={@on_close} data-nav-item tabindex="0">
          Close
        </.button>
      </header>

      <div class={[
        @activity != [] && "grid items-start gap-8 @4xl:grid-cols-[minmax(0,1fr)_21rem]",
        @activity == [] && "max-w-xl"
      ]}>
        <%!-- No eyebrow here: the masthead already names the subsystem, and a
             label outside the card would break top-alignment with the rail
             (every section label lives inside its card). --%>
        <div :if={@activity != []} class="@container min-w-0">
          {render_slot(@activity)}
        </div>

        <aside class="flex min-w-0 flex-col gap-3.5">
          <div class="glass-inset rounded-xl p-5">
            <h3 class="text-sm font-medium uppercase tracking-wider text-base-content/55">
              Status
            </h3>
            <div class="mt-3.5 flex items-center gap-2">
              <span class={["size-2 shrink-0 rounded-full", state_dot_class(@view.state)]}></span>
              <span class={["text-sm font-medium", state_text_class(@view.state)]}>
                {state_label(@view.state)}
              </span>
              <span :if={@view.state not in [:ok, :dormant]} class="text-xs text-base-content/55">
                {HealthBoard.tile_summary(@view)}
              </span>
            </div>

            <%!-- Composed all-clear: a deliberate confirmation, not floating copy.
                  A dormant subsystem has not earned it — nothing has run — so it
                  gets the one action that starts it instead. --%>
            <div
              :if={@buckets == [] and @view.state == :dormant}
              class="mt-3.5 flex items-start gap-2.5 border-t border-base-content/10 pt-3.5 text-sm"
            >
              <span class="mt-0.5 grid size-4 shrink-0 place-items-center rounded-full bg-base-content/10">
                <.icon name="hero-minus-mini" class="size-3 text-base-content/50" />
              </span>
              <span class="text-base-content/65">{HealthBoard.dormant_remedy(@view.component)}</span>
            </div>

            <div
              :if={@buckets == [] and @view.state != :dormant}
              class="mt-3.5 flex items-start gap-2.5 border-t border-base-content/10 pt-3.5 text-sm text-base-content/55"
            >
              <span class="mt-0.5 grid size-4 shrink-0 place-items-center rounded-full bg-success/15">
                <.icon name="hero-check-mini" class="size-3 text-success" />
              </span>
              <span class="font-medium text-base-content/65">No issues</span>
            </div>

            <div :if={@buckets != []} class="mt-3.5 border-t border-base-content/10 pt-3.5">
              <div class="mb-2 flex items-center justify-between">
                <h4 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
                  Issues
                </h4>
                <.button
                  variant="dismiss"
                  size="xs"
                  phx-click={@on_dismiss_all}
                  data-nav-item
                  tabindex="0"
                >
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
        </aside>
      </div>

      <div :if={@log_lines != [] or @logs != []} class="mt-8 flex flex-col gap-3.5">
        <%!-- Absence is the empty state: a subsystem with nothing recent in
              its rings gets no disclosure at all, rather than a permanent
              shut drawer that opens onto "No recent log lines." --%>
        <.disclosure
          :if={@log_lines != []}
          id="subsystem-logs"
          variant={:panel}
          open={DisclosureState.open?(@disclosures, "subsystem-logs")}
          label="Technical logs"
        >
          <%!-- A preview, not a log view: the latest lines, no scroller.
                Reading, following, filtering and search are the console's. --%>
          <div class="flex flex-col gap-0.5">
            <.log_line
              :for={entry <- @log_lines}
              entry={entry}
              show_component={@show_log_components}
            />
          </div>
          <div class="mt-3 flex justify-end">
            <.button
              variant="secondary"
              size="xs"
              navigate={~p"/console?subsystem=#{@view.component}"}
              data-nav-item
              tabindex="0"
            >
              Open in console <.icon name="hero-arrow-right-mini" class="size-3.5" />
            </.button>
          </div>
        </.disclosure>

        {render_slot(@logs)}
      </div>
    </section>
    """
  end

  @doc """
  The service's systemd journal, disclosed on demand.

  Not a second copy of the drill-in's logs: those are the subsystem's own
  structured entries, held in memory and empty at boot. The journal is the
  whole process's raw `journalctl` output, kept by systemd across restarts, so
  it is the only place on the page to read what happened before this run
  started — a crash included.

  Expanding is what subscribes. The tail is refcounted and `journalctl -f`
  runs only while someone is reading, so the disclosure is host-owned: its
  `on_toggle` event reaches `StatusLive`, which starts and stops the tail.
  """
  attr :lines, :list,
    default: [],
    doc: "[Console.Entry.t()] journal lines, oldest first; every one is `component: :systemd`"

  attr :open, :boolean, default: false
  attr :on_toggle, :string, default: "toggle_journal"
  attr :on_reconnect, :string, default: "journal_reconnect"

  def journal_panel(assigns) do
    ~H"""
    <%!-- Host-owned: opening it is what starts the tail. --%>
    <.disclosure
      id="subsystem-journal"
      variant={:panel}
      open={@open}
      event={@on_toggle}
      label="Systemd journal"
    >
      <div class="flex items-start justify-between gap-3">
        <p class="text-xs text-base-content/55">
          The service unit's own log, kept across restarts.
        </p>
        <%!-- The tail can die while the panel stays open — the unit
              restarts, the pipe breaks — and nothing else respawns it
              under a reader who is watching for the next line. --%>
        <.button
          variant="neutral"
          size="xs"
          phx-click={@on_reconnect}
          class="shrink-0"
          data-nav-item
          tabindex="0"
        >
          Reconnect
        </.button>
      </div>
      <%!-- The tail spawns on expand, so the first frame is routinely
            empty — it says what fills the space rather than reporting the
            emptiness the reader can already see. --%>
      <p :if={@lines == []} class="mt-3 text-xs text-base-content/55">
        Lines appear as the service writes them.
      </p>
      <%!-- Every entry is `component: :systemd` — the badge would say the
            same word on every row — and journalctl writes its own timestamp
            into the message, so the row's arrival stamp would print a second
            one beside it. --%>
      <.log_view
        :if={@lines != []}
        id="subsystem-journal-lines"
        lines={@lines}
        show_component={false}
        show_timestamp={false}
        class="mt-3 max-h-[32rem]"
      />
    </.disclosure>
    """
  end

  # Rail status line: color rides the dot and (when unhealthy) the label —
  # calm-when-healthy keeps the "Healthy" word in neutral ink.
  defp state_dot_class(:dormant), do: "bg-base-content/25"
  defp state_dot_class(:ok), do: "bg-success/55"
  defp state_dot_class(:warning), do: "bg-warning"
  defp state_dot_class(:error), do: "bg-error"

  defp state_text_class(:dormant), do: "text-base-content/55"
  defp state_text_class(:ok), do: "text-base-content/65"
  defp state_text_class(:warning), do: "text-warning"
  defp state_text_class(:error), do: "text-error"

  defp state_label(:dormant), do: "Not configured"
  defp state_label(:ok), do: "Healthy"
  defp state_label(:warning), do: "Warning"
  defp state_label(:error), do: "Error"
end
