defmodule MediaCentaurWeb.Components.StatusWidgets.SelfUpdate do
  @moduledoc """
  Self-update Activity widget: version, cadence, auto-install, live apply progress.

  Rendered into the health-board drill-in's :activity slot via
  MediaCentaurWeb.StatusLive.ActivityWidgets, invoked with a plain data
  bundle (no change-tracking) from StatusLive.activity_bundle/1 — derive
  with Map.put/3, never assign/3.
  """
  use MediaCentaurWeb, :html

  import MediaCentaurWeb.Components.StatusWidgets.Shared

  alias MediaCentaurWeb.Live.SettingsLive.ReleaseNotes
  alias MediaCentaurWeb.Live.SettingsLive.SystemSection

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
    doc:
      "upgrade history, newest-first: [%{version, recorded_at, notes_body}] — notes_body is the version's CHANGELOG markdown (Changelog.for_version/1) or nil"

  def self_update_widget(assigns) do
    ~H"""
    <div class="card glass-inset" data-testid="self-update-widget">
      <div class="card-body">
        <%!-- Header: title + running version --%>
        <div class="flex items-center justify-between">
          <h2 class="card-title text-lg">Updates</h2>
          <span class="text-sm font-mono text-base-content/60">v{@version}</span>
        </div>

        <p class={["text-sm", SystemSection.tone_class(SystemSection.update_status_tone(@status))]}>
          {SystemSection.update_status_label(@status, @latest_release)}
        </p>

        <%!-- What's new in the available update (reuses the Settings renderer) --%>
        <div
          :if={@status == :update_available && @latest_release}
          class="mt-3 border-t border-base-content/10 pt-3"
          data-component="whats-new"
        >
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-2">
            What's new in v{Map.get(@latest_release, :version, "")}
          </h3>
          <ReleaseNotes.release_notes body={Map.get(@latest_release, :body, "")} class="text-xs" />
        </div>

        <%!-- Check cadence + automatic install --%>
        <div class="mt-3 text-xs text-base-content/50 space-y-0.5">
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
          <.settings_link section="updates" class="gap-2">
            <span class="text-base-content/50">Automatic install</span>
            <span class={if @auto_install?, do: "text-success", else: "text-base-content/40"}>
              {if @auto_install?, do: "on", else: "off"}
            </span>
          </.settings_link>
        </div>

        <%!-- History: recent versions, each expandable to its improvements --%>
        <div
          :if={@history != []}
          class="mt-3 border-t border-base-content/10 pt-3"
          data-component="update-history"
        >
          <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/50 mb-1">
            History
          </h3>
          <ul class="space-y-1">
            <li :for={entry <- @history} id={history_row_id(entry)}>
              <details :if={Map.get(entry, :notes_body)} class="group">
                <summary class="flex items-center justify-between text-xs cursor-pointer list-none py-0.5">
                  <span class="flex items-center gap-1.5">
                    <.icon
                      name="hero-chevron-right-mini"
                      class="size-3.5 shrink-0 text-base-content/40 transition-transform group-open:rotate-90"
                    />
                    <span class="font-mono text-base-content/70">v{entry.version}</span>
                  </span>
                  <span class="text-base-content/40">{history_date(entry.recorded_at)}</span>
                </summary>
                <div class="mt-1.5 mb-2 pl-5">
                  <ReleaseNotes.release_notes body={Map.get(entry, :notes_body)} class="text-xs" />
                </div>
              </details>
              <div
                :if={!Map.get(entry, :notes_body)}
                class="flex items-center justify-between text-xs pl-5 py-0.5"
              >
                <span class="font-mono text-base-content/70">v{entry.version}</span>
                <span class="text-base-content/40">{history_date(entry.recorded_at)}</span>
              </div>
            </li>
          </ul>
        </div>

        <%!-- Apply progress (unchanged) --%>
        <div :if={apply_active?(@apply_phase)} class="mt-3 space-y-1" data-component="apply-progress">
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

        <p :if={@apply_phase == :failed} class="mt-3 text-xs text-error" data-component="apply-failed">
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
  defp history_date(%DateTime{} = at), do: Calendar.strftime(at, "%H:%M · %b %-d, %Y")

  # Stable, unique iterator id (ADR-012). `recorded_at` makes it collision-proof
  # even if the same version appears twice (a deliberate downgrade-then-re-upgrade
  # records two rows, since dedup only compares against the newest entry).
  defp history_row_id(%{version: version, recorded_at: at}),
    do: "update-history-#{version}-#{DateTime.to_unix(at, :microsecond)}"
end
