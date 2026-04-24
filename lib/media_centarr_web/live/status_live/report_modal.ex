defmodule MediaCentarrWeb.StatusLive.ReportModal do
  @moduledoc """
  Modal shown when the user clicks "Report errors" on the Status page.

  Presents the active buckets in a radio list, shows a redacted payload
  preview, and on confirm emits a `push_event("error_reports:open_issue",
  %{url: url})` that the `ErrorReport` JS hook handles with `window.open`.
  """
  use MediaCentarrWeb, :live_component

  alias MediaCentarr.ErrorReports.{EnvMetadata, IssueUrl}

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
  def render(assigns) do
    selected_bucket =
      Enum.find(assigns.buckets, &(&1.fingerprint == assigns.selected))

    env = EnvMetadata.collect()

    preview =
      if selected_bucket do
        {:ok, _url, flags} = IssueUrl.build(selected_bucket, env)

        %{
          title: IssueUrl.format_title(selected_bucket),
          body: IssueUrl.format_body(selected_bucket, env, selected_bucket.sample_entries, flags),
          flags: flags
        }
      end

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
            Send this error report to the Media Centarr developer?
          </h2>

          <div class="alert alert-warning text-sm">
            <span>
              Review the report below before submitting. It's been automatically
              scrubbed of paths, UUIDs, API keys, IPs, emails, and configured URLs —
              but please glance for anything else personal (titles of private files,
              usernames in error messages, etc.) before confirming.
              This will open a public GitHub issue.
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

          <div
            :if={@preview && :truncated_log_context in @preview.flags}
            class="alert alert-info text-sm"
          >
            <span>Log context truncated to fit GitHub's URL size limit.</span>
          </div>
        </div>

        <div class="px-6 pt-4 pb-6 flex flex-col items-center gap-2 border-t border-base-300">
          <button
            class="btn btn-primary"
            phx-click={JS.push("report_confirm", value: %{fingerprint: @selected})}
            disabled={is_nil(@selected)}
          >
            Confirm &amp; open GitHub
          </button>
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
