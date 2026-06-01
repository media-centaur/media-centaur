defmodule MediaCentaurWeb.StatusLive.ReportModal do
  @moduledoc """
  Modal shown when the user clicks "Report errors" on the Status page.

  Presents the active buckets in a radio list and a redacted payload preview.
  On confirm, `StatusLive` submits via `ErrorReports.submit_report/2` to the
  private reports inbox; the result is rendered here — `{:ok, url}` as a sent
  confirmation, `{:fallback, bundle}` as copyable text when no token is
  configured or the network is unavailable.

  > Interim single-screen modal; the guided 3-step consent flow is the next
  > Milestone-2 step.
  """
  use MediaCentaurWeb, :live_component

  alias MediaCentaur.ErrorReports.{EnvMetadata, ReportPayload}

  @impl true
  def update(assigns, socket) do
    selected =
      case assigns.buckets do
        [first | _] -> first.fingerprint
        _ -> nil
      end

    {:ok, assign(socket, Map.put(assigns, :selected, selected))}
  end

  @impl true
  def handle_event("select", %{"fingerprint" => fp}, socket) do
    {:noreply, assign(socket, :selected, fp)}
  end

  # `report_confirm` and `report_cancel` are NOT handled here — they
  # bubble up to StatusLive because the template omits `target: @myself`
  # on those bindings. Keeping the submission logic in the parent keeps
  # the modal a pure view.

  @impl true
  def render(%{report_result: result} = assigns) when not is_nil(result) do
    ~H"""
    <div
      id="error-report-modal"
      class="modal-backdrop"
      data-state="open"
      data-testid="report-modal"
      phx-click="report_cancel"
      phx-window-keydown="report_cancel"
      phx-key="Escape"
    >
      <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
        <div :if={match?({:ok, _}, @report_result)} class="p-6 flex flex-col gap-3">
          <h2 class="text-lg font-semibold">Report sent</h2>
          <p class="text-sm text-base-content/70">
            Thanks — this has been sent to the development team.
          </p>
          <a href={elem(@report_result, 1)} target="_blank" rel="noopener" class="link text-sm">
            View the report
          </a>
          <.button variant="dismiss" phx-click="report_cancel">Close</.button>
        </div>

        <div :if={match?({:fallback, _}, @report_result)} class="p-6 flex flex-col gap-3">
          <h2 class="text-lg font-semibold">Copy this report</h2>
          <p class="text-sm text-base-content/70">
            We couldn't send it automatically. Copy the text below and send it to the
            developer — nothing leaves your machine until you do.
          </p>
          <textarea
            data-testid="report-fallback"
            readonly
            rows="12"
            class="textarea textarea-bordered w-full font-mono text-xs"
          >{elem(@report_result, 1)}</textarea>
          <.button variant="dismiss" phx-click="report_cancel">Close</.button>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    selected_bucket =
      Enum.find(assigns.buckets, &(&1.fingerprint == assigns.selected))

    preview = selected_bucket && ReportPayload.build(selected_bucket, EnvMetadata.collect())

    assigns = assign(assigns, :preview, preview)

    ~H"""
    <div
      id="error-report-modal"
      class="modal-backdrop"
      data-state="open"
      data-testid="report-modal"
      phx-click="report_cancel"
      phx-window-keydown="report_cancel"
      phx-key="Escape"
    >
      <div class="modal-panel" phx-click={%Phoenix.LiveView.JS{}}>
        <div class="px-6 pt-6 pb-3 flex flex-col gap-3">
          <h2 class="text-lg font-semibold">
            Send this error report to the Media Centaur developer?
          </h2>

          <div class="alert alert-warning text-sm">
            <span>
              Review the report below before sending. It's been automatically
              scrubbed of paths, UUIDs, API keys, IPs, emails, and configured URLs —
              but please glance for anything else personal (titles of private files,
              usernames in error messages, etc.) before confirming. It's sent
              privately to the developer — not posted anywhere public.
            </span>
          </div>
        </div>

        <div class="px-6 flex-1 min-h-0 overflow-y-auto flex flex-col gap-4">
          <fieldset class="space-y-1">
            <legend class="text-sm text-base-content/70 mb-1">Which error?</legend>
            <label
              :for={bucket <- @buckets}
              class="flex items-start gap-2 cursor-pointer p-2 rounded hover:bg-base-200"
            >
              <input
                type="radio"
                class="radio radio-sm mt-1"
                name="bucket"
                value={bucket.fingerprint}
                checked={bucket.fingerprint == @selected}
                phx-click={
                  JS.push("select", value: %{fingerprint: bucket.fingerprint}, target: @myself)
                }
              />
              <span class="flex-1 min-w-0">
                <span class="font-mono text-xs block truncate">{bucket.display_title}</span>
                <span class="text-xs text-base-content/60">
                  ×{bucket.count} · {bucket.component}
                </span>
              </span>
            </label>
          </fieldset>

          <div
            :if={@preview}
            class="bg-base-200 rounded p-4 font-mono text-xs whitespace-pre-wrap"
          >
            <div class="text-base-content/70 mb-2 font-sans text-sm">Preview</div>
            <div><span class="font-semibold">Title:</span> {@preview.title}</div>
            <div class="mt-2">{@preview.body}</div>
          </div>
        </div>

        <div class="px-6 pt-4 pb-6 flex flex-col items-center gap-2 border-t border-base-300">
          <.button
            variant="primary"
            phx-click={JS.push("report_confirm", value: %{fingerprint: @selected})}
            disabled={is_nil(@selected)}
          >
            Send to the developer
          </.button>
          <a
            href="#"
            class="link link-hover text-sm text-base-content/60"
            phx-click="report_cancel"
          >
            No, don't send
          </a>
        </div>
      </div>
    </div>
    """
  end
end
