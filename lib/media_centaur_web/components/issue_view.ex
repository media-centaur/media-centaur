defmodule MediaCentaurWeb.Components.IssueView do
  @moduledoc """
  Ephemeral modal showing everything known about one `ErrorReports.Bucket`:
  title, subsystem (name + glyph), severity, occurrence count + time range, and
  the raw sample log lines. The footer hands off to the persistent report
  wizard (`on_report`). The subsystem's plain-language briefing is deliberately
  *not* repeated here — it lives at the top of the drill-in this modal opens
  from; the incident modal stays about the incident.

  Presentation only. Subsystem label/glyph come from `HealthBoard`, which are
  total functions (unknown components normalize to `:system`).
  """
  use MediaCentaurWeb, :html

  alias MediaCentaur.ErrorReports.Bucket
  alias MediaCentaurWeb.StatusLive.HealthBoard

  attr :bucket, Bucket, default: nil, doc: "the selected incident, or nil when the modal is closed"
  attr :on_close, :string, default: "close_incident"
  attr :on_report, :string, default: "report_incident_from_issue"
  attr :on_dismiss, :string, default: "dismiss_incident"

  def issue_view(assigns) do
    ~H"""
    <.modal
      id="issue-view"
      open={!is_nil(@bucket)}
      dismiss={:ephemeral}
      on_close={@on_close}
      data-detail-mode={!is_nil(@bucket) && "modal"}
      panel_class="flex flex-col max-h-[calc(85*var(--pvh))]"
    >
      <div :if={@bucket} class="flex flex-col min-h-0">
        <div class="px-6 pt-5 pb-4 border-b border-base-300">
          <div class="flex items-start gap-3">
            <span class={[
              "size-2.5 rounded-full shrink-0 mt-1.5",
              @bucket.severity == :warning && "bg-warning",
              @bucket.severity in [:error, :critical] && "bg-error"
            ]} />
            <div class="min-w-0">
              <h2 class="text-lg font-semibold leading-snug">{@bucket.display_title}</h2>
              <p class="text-xs text-base-content/55 mt-1 flex items-center gap-1.5">
                <.icon name={HealthBoard.glyph(@bucket.component)} class="size-4" />
                {HealthBoard.label(@bucket.component)} · {@bucket.count}× · {Calendar.strftime(
                  @bucket.first_seen,
                  "%b %-d, %H:%M"
                )} → {Calendar.strftime(@bucket.last_seen, "%b %-d, %H:%M")}
              </p>
            </div>
          </div>
        </div>

        <div class="px-6 py-4 flex-1 min-h-0 overflow-y-auto space-y-4">
          <div :if={@bucket.sample_entries != []} class="space-y-1.5">
            <h3 class="text-xs font-medium uppercase tracking-wider text-base-content/55">
              Recent log lines
            </h3>
            <div class="glass-inset rounded-lg px-3 py-2 text-xs font-mono text-base-content/60 space-y-1">
              <p :for={entry <- @bucket.sample_entries}>
                <span class="text-base-content/55">
                  {Calendar.strftime(entry.timestamp, "%H:%M:%S")}
                </span>
                {entry.message}
              </p>
            </div>
          </div>
        </div>

        <div class="px-6 py-4 border-t border-base-300 flex items-center gap-2">
          <.button
            variant="dismiss"
            phx-click={@on_dismiss}
            phx-value-fingerprint={@bucket.fingerprint}
            data-nav-item
            tabindex="0"
          >
            Dismiss
          </.button>
          <div class="flex-1"></div>
          <.button variant="dismiss" phx-click={@on_close} data-nav-item tabindex="0">
            Close
          </.button>
          <.button
            variant="primary"
            phx-click={@on_report}
            phx-value-fingerprint={@bucket.fingerprint}
            data-nav-item
            tabindex="0"
          >
            Report this
          </.button>
        </div>
      </div>
    </.modal>
    """
  end
end
